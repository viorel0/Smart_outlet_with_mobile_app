#include "esp_log.h"
#include "host/ble_hs.h" 
#include "host/ble_gatt.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>
#include "esp_mac.h"

extern void wifi_init_sta(void);
extern void update_and_save_credentials(const char *new_ssid, const char *new_pass);
extern bool ble_mode_active;

uint16_t ssid_handle;
uint16_t pass_handle;
uint16_t mac_handle;

static char temp_ssid[32] = {0};
static char temp_pass[64] = {0};


static volatile bool ble_running = false;

static const struct ble_gatt_svc_def gatt_svr_svcs[];
static int get_ble_data(uint16_t conn_handle, uint16_t attr_handle,
                        struct ble_gatt_access_ctxt *ctxt, void *arg);
static int bluenimble_gap_event(struct ble_gap_event *event, void *arg);

// Configurare publicitate BLE
void porneste_publicitatea_ble(void) {
    struct ble_gap_adv_params adv_params;
    struct ble_hs_adv_fields fields;
    int rc;

    memset(&fields, 0, sizeof(fields));
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    
    const char *nume_dispozitiv = "ESP32-Energy-Monitor";
    fields.name = (uint8_t *)nume_dispozitiv;
    fields.name_len = strlen(nume_dispozitiv);
    fields.name_is_complete = 1;

    rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        printf("[BLE] Eroare la configurarea pachetului GAP: %d\n", rc);
        return;
    }

    memset(&adv_params, 0, sizeof(adv_params));
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND; 
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN; 

    rc = ble_gap_adv_start(BLE_ADDR_PUBLIC, NULL, BLE_HS_FOREVER, &adv_params, bluenimble_gap_event, NULL);
    if (rc != 0) {
        printf("[BLE] Eroare critică la deschiderea antenei: %d\n", rc);
    } else {
        printf("[BLE] Antena emite! Te poți CONECTA la dispozitiv din Flutter.\n");
    }
}

static int bluenimble_gap_event(struct ble_gap_event *event, void *arg) {
    switch (event->type) {
        case BLE_GAP_EVENT_CONNECT:
            printf("[BLE] Un dispozitiv s-a CONECTAT local.\n");
            break;

        case BLE_GAP_EVENT_DISCONNECT:
            printf("[BLE] Dispozitiv DECONECTAT! Repornim imediat antena...\n");
            porneste_publicitatea_ble(); 
            break;

        case BLE_GAP_EVENT_ADV_COMPLETE:
            printf("[BLE] Publicitatea s-a oprit automat. O repornim...\n");
            porneste_publicitatea_ble();
            break;
    }
    return 0;
}

static void bluenimble_on_sync(void) {
    printf("[BLE] Hardware sincronizat. Activăm vizibilitatea...\n");
    porneste_publicitatea_ble();
}


void bluenimble_host_task(void *param) {
    nimble_port_run(); 
    vTaskDelete(NULL);
}

// initializare BLE
void init_ble(void) {
    if (ble_running) {
        printf("[BLE] BLE deja rulează, ignorăm init duplicat.\n");
        return;
    }

    esp_err_t ret = nimble_port_init();
    if (ret != ESP_OK) {
        printf("[BLE] EROARE: nimble_port_init() a eșuat cu %d! BLE nu poate porni.\n", ret);
        ble_running = false;
        return;
    }

    ble_svc_gap_init();
    ble_svc_gatt_init();
    
    ble_gatts_count_cfg(gatt_svr_svcs);
    ble_gatts_add_svcs(gatt_svr_svcs);
    
    ble_svc_gap_device_name_set("ESP32-Energy-Monitor");
    ble_hs_cfg.sync_cb = bluenimble_on_sync;

    nimble_port_freertos_init(bluenimble_host_task);
    ble_running = true;
    printf("[BLE] NimBLE pornit cu succes! Așteptare evenimente...\n");
}

void stop_ble(void) {
    if (!ble_running) {
        printf("[BLE] BLE nu rulează, ignorăm stop duplicat.\n");
        return;
    }
    printf("[BLE] Oprire solicitată de sistem...\n");
    nimble_port_stop();
}

//oprire ble
static void ble_deferred_stop_task(void *param) {
    vTaskDelay(pdMS_TO_TICKS(100));
    if (!ble_running) {
        printf("[BLE] Oprire amânată: BLE deja oprit, ignorăm.\n");
        vTaskDelete(NULL);
        return;
    }
    ble_running = false;
    printf("[BLE] nimble_port_run() s-a terminat. Curățăm resurse...\n");

    int ret = nimble_port_deinit();
    if (ret != 0) {
        printf("[BLE] Warning: nimble_port_deinit a returnat %d\n", ret);
    }
    if ( ret == ESP_OK ) {
        printf("[BLE] nimble_port_deinit a finalizat cu succes.\n");
    }

    nimble_port_freertos_deinit();
    
    printf("[BLE] Stiva NimBLE complet dezactivată și ștearsă din RAM.\n");
    
    if (ble_mode_active) {
        printf("[BLE] Schimbare automată de regim radio. Pornim Wi-Fi...\n");
        ble_mode_active = false;
        wifi_init_sta(); 
    }

    vTaskDelete(NULL);
}


static int get_ble_data(uint16_t conn_handle, uint16_t attr_handle,
                        struct ble_gatt_access_ctxt *ctxt, void *arg) 
{
    if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        char buffer_temporar[64] = {0};
        uint16_t lungime_text;

        ble_hs_mbuf_to_flat(ctxt->om, buffer_temporar, sizeof(buffer_temporar) - 1, &lungime_text);
        buffer_temporar[lungime_text] = '\0';

        if (attr_handle == ssid_handle) {
            strncpy(temp_ssid, buffer_temporar, sizeof(temp_ssid) - 1);
            printf("[BLE] Flutter a scris SSID: %s\n", temp_ssid);
        } 
        else if (attr_handle == pass_handle) {
            strncpy(temp_pass, buffer_temporar, sizeof(temp_pass) - 1);
            printf("[BLE] Flutter a scris Parolă: %s\n", temp_pass);
        }

        if (strlen(temp_ssid) > 0 && strlen(temp_pass) > 0) {
            printf("[BLE] Credențiale primite! Salvăm datele în NVS Flash...\n");
            
            update_and_save_credentials(temp_ssid, temp_pass);

            memset(temp_ssid, 0, sizeof(temp_ssid));
            memset(temp_pass, 0, sizeof(temp_pass));

            printf("[BLE] Credențiale OK! Lansăm oprirea BLE din task separat...\n");
            xTaskCreate(ble_deferred_stop_task, "ble_stop", 2048, NULL, 5, NULL); 
        }
        return 0;
    }
    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        if (attr_handle == mac_handle) {
            uint8_t mac[6];

            esp_read_mac(mac, ESP_MAC_WIFI_STA);
            char mac_str[18];
        
            snprintf(mac_str, sizeof(mac_str), "%02X:%02X:%02X:%02X:%02X:%02X",
                     mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
            
            printf("[BLE] Flutter cere adresa MAC. Trimitem string-ul: %s\n", mac_str);

            int rc = os_mbuf_append(ctxt->om, mac_str, strlen(mac_str));
            return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
        }
    }
    return 0;
}

//caracteristici și servicii GATT
static const struct ble_gatt_svc_def gatt_svr_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = BLE_UUID128_DECLARE(0x4f, 0xaf, 0xc2, 0x01, 0x1f, 0xb5, 0x45, 0x9e, 0x8f, 0xcc, 0xc5, 0xc9, 0xc3, 0x31, 0x91, 0x4b),
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = BLE_UUID128_DECLARE(0xbe, 0xb5, 0x48, 0x3e, 0x36, 0xe1, 0x46, 0x88, 0xb7, 0xf5, 0xea, 0x07, 0x36, 0x1b, 0x26, 0xa8),
                .val_handle = &ssid_handle,
                .access_cb = get_ble_data, 
                .flags = BLE_GATT_CHR_F_WRITE
            },
            {
                .uuid = BLE_UUID128_DECLARE(0xcb, 0xa1, 0xd9, 0x4e, 0x28, 0xe1, 0x4b, 0xc8, 0xa7, 0xf5, 0xfa, 0x07, 0x36, 0x1b, 0x26, 0xb9),
                .val_handle = &pass_handle,
                .access_cb = get_ble_data, 
                .flags = BLE_GATT_CHR_F_WRITE
            },
            {
                .uuid = BLE_UUID128_DECLARE(0xcb, 0xa1, 0xd9, 0x4e, 0x28, 0xe1, 0x4b, 0xc8, 0xa7, 0xf5, 0xfa, 0x07, 0x36, 0x1b, 0x26, 0xc1),
                .val_handle = &mac_handle,
                .access_cb = get_ble_data, 
                .flags = BLE_GATT_CHR_F_READ
            },
            {0} 
        },
    },
    {0}, 
};