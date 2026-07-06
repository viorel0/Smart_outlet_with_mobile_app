#include "wifisending.h"
#include "bluenimble.h"
#include "driver/gpio.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>
#include "esp_http_client.h"
#include "cJSON.h"
#include "freertos/event_groups.h"
#include "esp_crt_bundle.h"
#include "esp_netif_sntp.h"
#include "esp_mac.h"
#include "nvs.h"
#include "nvs_flash.h"

#define BUTTON_BLE 7 //k3
#define DEBOUNCE_MS 50

#define RELAY_SCREEN_BUTTON 6 //k4
#define RELAY_COMMAND_PIN 17 //comanda catre releu

#define RETRY 5

// ============ UDP CONFIG ============
#define TARGET_IP "255.255.255.255"
#define TARGET_PORT 5005
// ====================================

extern float current_value_for_send;
extern float voltage_value_for_send;

static const char *TAG = "wifi_mgr";
static int s_retry_num = 0;

static int udp_sock = -1;
static struct sockaddr_in dest_addr;

volatile bool udp_enabled = true;

static uint8_t full_frame[2632] __attribute__((aligned(4)));

//aceleasi ca in aplicatia mobila
#define SUPABASE_URL ""
#define SUPABASE_KEY ""

extern EventGroupHandle_t wifi_event_group;
volatile bool stare_releu_locala;
volatile bool s_a_modificat_din_buton;
volatile bool s_a_sincronizat_initial;

// Inițializare socket UDP
void udp_socket_init(void) {
  if (udp_sock >= 0) {
    close(udp_sock);
  }

  udp_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (udp_sock < 0) {
    ESP_LOGE(TAG, "Nu am putut crea socket UDP: errno %d", errno);
    return;
  }

  memset(&dest_addr, 0, sizeof(dest_addr));
  dest_addr.sin_addr.s_addr = inet_addr(TARGET_IP);
  dest_addr.sin_family = AF_INET;
  dest_addr.sin_port = htons(TARGET_PORT);

  int sndbuf = 4096; 
  setsockopt(udp_sock, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof(sndbuf));

  struct timeval send_timeout = {.tv_sec = 0, .tv_usec = 16000};
  setsockopt(udp_sock, SOL_SOCKET, SO_SNDTIMEO, &send_timeout,
             sizeof(send_timeout));

  int broadcast = 1;
  setsockopt(udp_sock, SOL_SOCKET, SO_BROADCAST, &broadcast, sizeof(broadcast));

  ESP_LOGI(TAG, "Socket UDP creat (fd=%d), target: %s:%d", udp_sock, TARGET_IP,
           TARGET_PORT);
}

void udp_socket_deinit(void) {
  if (udp_sock >= 0) {
    close(udp_sock);
    udp_sock = -1;
    ESP_LOGI(TAG, "Socket UDP închis.");
  }
}

void send_waveform_udp(float *wavev, float *wavei, float *wavefftv,
                       float *waveffti) {
  if (udp_sock < 0 || !udp_enabled)
    return;
  
  esp_read_mac(&full_frame[0], ESP_MAC_WIFI_STA);

  memcpy(&full_frame[8], wavev, 800);       // 200 × float32 = 800 bytes
  memcpy(&full_frame[808], wavei, 800);     // 200 × float32 = 800 bytes
  memcpy(&full_frame[1608], wavefftv, 512); // 128 × float32 = 512 bytes
  memcpy(&full_frame[2120], waveffti, 512); // 128 × float32 = 512 bytes

  int ret = sendto(udp_sock, full_frame, 2632, 0, (struct sockaddr *)&dest_addr,
                   sizeof(dest_addr));
  if (ret < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
    ESP_LOGW(TAG, "Eroare sendto UDP: errno %d", errno);
  }
}

extern void wifi_processing_task(void *pvParameters);
void cloud_sync_task(void *pvParameters);
bool ble_mode_active = false;
extern TaskHandle_t wifi_proc_task_hdl;
extern TaskHandle_t cloud_sync_task_hdl;


void stop_wifi_and_network_tasks(void) {
  ESP_LOGW(TAG, "Oprire Wi-Fi și curățare task-uri din RAM...");

  if (wifi_proc_task_hdl != NULL) {
    vTaskDelete(wifi_proc_task_hdl);
    wifi_proc_task_hdl = NULL;
  }

  if (cloud_sync_task_hdl != NULL) {
    vTaskDelete(cloud_sync_task_hdl);
    cloud_sync_task_hdl = NULL;
  }

  udp_socket_deinit();
  esp_wifi_stop();
}

char set_ssid[32];
char set_pass[64];

void load_credentials_from_nvs(void) {
  nvs_handle_t my_handle;
  esp_err_t err = nvs_open("wifi_store", NVS_READONLY, &my_handle);
  if (err == ESP_OK) {
    size_t ssid_len = sizeof(set_ssid);
    size_t pass_len = sizeof(set_pass);

    nvs_get_str(my_handle, "ssid", set_ssid, &ssid_len);
    nvs_get_str(my_handle, "pass", set_pass, &pass_len);

    nvs_close(my_handle);
    ESP_LOGI(TAG, "[NVS] Date încărcate cu succes din Flash! SSID: %s",
             set_ssid);
  } else {
    ESP_LOGW(TAG, "[NVS] Nu există date salvate. Aparatul este virgin.");
  }
}

void update_and_save_credentials(const char *new_ssid, const char *new_pass) {

  strncpy(set_ssid, new_ssid, sizeof(set_ssid) - 1);
  strncpy(set_pass, new_pass, sizeof(set_pass) - 1);

  nvs_handle_t my_handle;
  esp_err_t err = nvs_open("wifi_store", NVS_READWRITE, &my_handle);
  if (err == ESP_OK) {
    nvs_set_str(my_handle, "ssid", set_ssid);
    nvs_set_str(my_handle, "pass", set_pass);
    nvs_commit(my_handle);
    nvs_close(my_handle);
    ESP_LOGI(TAG, "[NVS] Credențiale noi arse pe Flash-ul ESP32!");
  } else {
    ESP_LOGE(TAG, "[NVS] Eroare la deschiderea Flash-ului pentru scriere!");
  }
}

void wifi_connect(void) {
  wifi_config_t wifi_config = {0};
  strncpy((char *)wifi_config.sta.ssid, set_ssid,
          sizeof(wifi_config.sta.ssid) - 1);
  strncpy((char *)wifi_config.sta.password, set_pass,
          sizeof(wifi_config.sta.password) - 1);

  esp_err_t ret = esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
  if (ret != ESP_OK) {
    ESP_LOGE(TAG, "wifi_set_config a eșuat: %s (Wi-Fi posibil oprit)",
             esp_err_to_name(ret));
    return;
  }
  ret = esp_wifi_connect();
  if (ret != ESP_OK) {
    ESP_LOGE(TAG, "wifi_connect a eșuat: %s", esp_err_to_name(ret));
  }
}

static void event_handler(void *arg, esp_event_base_t event_base,
                          int32_t event_id, void *event_data) {
  if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
    wifi_connect();
  } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
    if (ble_mode_active) {
      ESP_LOGW(TAG,"Deconectare controlată pentru mod BLE. Ignorăm reconectarea.");
      return;
    }
    if (s_retry_num < RETRY) {
      wifi_connect();
      s_retry_num++;
      ESP_LOGI(TAG, "Încercare reconectare router...");
    } else {
      ESP_LOGE(TAG, "Conexiune eșuată permanent! Activare automată BLE...");
      s_retry_num = 0;
      ble_mode_active = true; 

      stop_wifi_and_network_tasks();
      esp_wifi_deinit();
      init_ble(); 
    }
  } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
    ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
    ESP_LOGI(TAG, "Am primit IP:" IPSTR, IP2STR(&event->ip_info.ip));
    xEventGroupSetBits(wifi_event_group, BIT(0));
    s_retry_num = 0;
    ble_mode_active = false;

    udp_socket_init();

    if (wifi_proc_task_hdl == NULL) {
      xTaskCreatePinnedToCore(wifi_processing_task, "WiFi_Proc", 8192, NULL, 7,
                              &wifi_proc_task_hdl, 0);
    }
    if (cloud_sync_task_hdl == NULL) {
      xTaskCreatePinnedToCore(cloud_sync_task, "cloud_sync_task",
                              8192, NULL, 3, &cloud_sync_task_hdl, 0);
    }
  }
}

void wifi_init_sta(void) {
  static bool s_system_inited = false;

  if (!s_system_inited) {
    load_credentials_from_nvs();
  }

  if (strlen(set_ssid) == 0) {
    ESP_LOGW(TAG,
             "NVS gol! Trecem direct în regim de configurare BLE...");
    ble_mode_active = true;
    init_ble();
    return;
  }

  if (!s_system_inited) {
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID, &event_handler, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        IP_EVENT, IP_EVENT_STA_GOT_IP, &event_handler, NULL, NULL));

    s_system_inited = true;
  }

  wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_wifi_init(&cfg));

  ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
  esp_wifi_set_band_mode(WIFI_BAND_MODE_2G_ONLY);
  esp_wifi_set_ps(WIFI_PS_NONE);
  ESP_ERROR_CHECK(esp_wifi_start());

  ESP_LOGI(TAG, "wifi_init_sta a finalizat configurarea.");
}

void button_control_task(void *pvParameters) {
  gpio_config_t io_conf = {
      .intr_type = GPIO_INTR_DISABLE,
      .mode = GPIO_MODE_INPUT,
      .pin_bit_mask = (1ULL << BUTTON_BLE),
      .pull_up_en = GPIO_PULLUP_ENABLE,
      .pull_down_en = GPIO_PULLDOWN_DISABLE,
  };
  gpio_config(&io_conf);

  while (1) {
    if (gpio_get_level(BUTTON_BLE) == 0) {
      vTaskDelay(pdMS_TO_TICKS(DEBOUNCE_MS));

      if (gpio_get_level(BUTTON_BLE) == 0) {
        if (!ble_mode_active) {
          printf(
              ">>> [BUTON] Trecere în MOD CONFIGURARE BLE. Oprim Wi-Fi...\n");
          ble_mode_active = true;

          stop_wifi_and_network_tasks();
          esp_wifi_deinit();
          init_ble();
        } else {
          printf(">>> [BUTON] BLE deja activ, așteptăm credențiale de la "
                 "Flutter.\n");
        }

        while (gpio_get_level(BUTTON_BLE) == 0) {
          vTaskDelay(pdMS_TO_TICKS(10));
        }
      }
    }
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

void relay_button_task(void *pvParameters){
  //Configurare input
  gpio_config_t io_conf_in = {
    .intr_type = GPIO_INTR_DISABLE,
    .mode = GPIO_MODE_INPUT,
    .pin_bit_mask = (1ULL << RELAY_SCREEN_BUTTON),
    .pull_up_en = GPIO_PULLUP_ENABLE, 
    .pull_down_en = GPIO_PULLDOWN_DISABLE,
  };
  gpio_config(&io_conf_in);

  //Configurare OUTPUT (Pinul către releu)
  gpio_config_t io_conf_out = {
    .intr_type = GPIO_INTR_DISABLE,
    .mode = GPIO_MODE_OUTPUT,
    .pin_bit_mask = (1ULL << RELAY_COMMAND_PIN),
    .pull_up_en = GPIO_PULLUP_DISABLE,
    .pull_down_en = GPIO_PULLDOWN_DISABLE,
  };
  gpio_config(&io_conf_out);

  int last_status = 1;

  gpio_set_level(RELAY_COMMAND_PIN, 0);

  while (1) {
    if (!s_a_sincronizat_initial) {
        vTaskDelay(pdMS_TO_TICKS(20));
        continue; 
    }

    int status_curent = gpio_get_level(RELAY_SCREEN_BUTTON);

    if (last_status == 1 && status_curent == 0) {
      vTaskDelay(pdMS_TO_TICKS(50)); 
      
      if (gpio_get_level(RELAY_SCREEN_BUTTON) == 0) { 
        printf("[HARDWARE] Buton apasat fizic!\n");
        stare_releu_locala = !stare_releu_locala;
        gpio_set_level(RELAY_COMMAND_PIN, stare_releu_locala ? 0 : 1); 
        
        s_a_modificat_din_buton = true;
        
        printf("Releu este %s\n", stare_releu_locala ? "PORNIT" : "OPRIT");
      }
    }

    last_status = status_curent;
    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

typedef struct {
    char *data;
    int len;
} http_response_t;

static esp_err_t http_event_handler(esp_http_client_event_t *evt) {
    http_response_t *resp = (http_response_t *)evt->user_data;
    if (resp == NULL) return ESP_OK;

    switch (evt->event_id) {
        case HTTP_EVENT_ON_DATA: {
            char *new_data = realloc(resp->data, resp->len + evt->data_len + 1);
            if (new_data == NULL) {
                ESP_LOGE(TAG, "realloc eșuat pentru buffer HTTP");
                return ESP_FAIL;
            }
            resp->data = new_data;
            memcpy(resp->data + resp->len, evt->data, evt->data_len);
            resp->len += evt->data_len;
            resp->data[resp->len] = '\0';
            break;
        }
        default:
            break;
    }
    return ESP_OK;
}

extern portMUX_TYPE kwh_mux;
extern float kwh_this_minute;
extern float current_value_for_send;
extern float voltage_value_for_send;
extern float active_power_for_send;
extern float apparent_power_for_send;
extern float reactive_power_for_send;
extern float power_factor_for_send;
extern float frequency_for_send;
extern float thd_i_for_send;
extern float thd_v_for_send;

void cloud_sync_task(void *pvParameters) {
    static int counter_for_post_60s = 0;
    static int counter_for_send_5s = 0;
    static bool sntp_initialized = false;

    ESP_LOGI(TAG, "Task-ul de cloud a pornit. Asteptam conexiunea Wi-Fi...");

    xEventGroupWaitBits(wifi_event_group, BIT(0), pdFALSE, pdTRUE, portMAX_DELAY);
    ESP_LOGI(TAG, "Conexiune Wi-Fi stabilită! Începem sincronizarea cu cloud-ul...");

    if (!sntp_initialized) {
        esp_sntp_config_t config_ntp = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
        esp_netif_sntp_init(&config_ntp);
        sntp_initialized = true;
    }

    if (esp_netif_sntp_sync_wait(pdMS_TO_TICKS(10000)) == ESP_OK) {
        time_t now;
        struct tm timeinfo;
        time(&now);
        localtime_r(&now, &timeinfo);
        ESP_LOGI(TAG, "Ora setata! Suntem in anul: %d", (1900 + timeinfo.tm_year));
    } else {
        ESP_LOGE(TAG, "Eroare la preluarea orei! HTTPS ar putea pica.");
    }

    ESP_LOGI(TAG, "Incepem sincronizarea initiala cu Supabase...");

    static uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);

    static char mac_str[18];
    snprintf(mac_str, sizeof(mac_str), "%02X:%02X:%02X:%02X:%02X:%02X",
              mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    printf("[CLOUD] Adresa MAC a dispozitivului: %s\n", mac_str);

    static char request_url[256];
    snprintf(request_url, sizeof(request_url), "%s/rest/v1/devices?mac_address=eq.%s", SUPABASE_URL, mac_str);

    static http_response_t resp = { .data = NULL, .len = 0 };
    esp_http_client_config_t config = {
        .url = request_url,
        .method = HTTP_METHOD_GET,
        .event_handler = http_event_handler,
        .user_data = &resp,
        .keep_alive_enable = true,
        .timeout_ms = 3000,
    };
    
    esp_http_client_handle_t client = esp_http_client_init(&config);

    esp_http_client_set_header(client, "apikey", SUPABASE_KEY);
    esp_http_client_set_header(client, "Authorization", "Bearer " SUPABASE_KEY);
    esp_http_client_set_header(client, "Content-Type", "application/json");
    esp_http_client_set_header(client, "Accept", "application/json");
    esp_http_client_set_header(client, "Prefer", "return=minimal");

    static http_response_t patch_resp = { .data = NULL, .len = 0 };
    esp_http_client_config_t patch_config = {
        .url = request_url,
        .method = HTTP_METHOD_PATCH,
        .event_handler = http_event_handler,
        .user_data = &patch_resp,
        .keep_alive_enable = true,
        .timeout_ms = 3000,
    };

    esp_http_client_handle_t patch_client = esp_http_client_init(&patch_config);
    esp_http_client_set_header(patch_client, "apikey", SUPABASE_KEY);
    esp_http_client_set_header(patch_client, "Authorization", "Bearer " SUPABASE_KEY);
    esp_http_client_set_header(patch_client, "Content-Type", "application/json");
    esp_http_client_set_header(patch_client, "Accept", "application/json");
    esp_http_client_set_header(patch_client, "Prefer", "return=minimal");

    
    static char boot_relay_body[64];
    snprintf(boot_relay_body, sizeof(boot_relay_body), "{\"relay_status\": true}");
    esp_http_client_set_post_field(patch_client, boot_relay_body, strlen(boot_relay_body));
    esp_err_t err_boot_relay = esp_http_client_perform(patch_client);
    if (err_boot_relay == ESP_OK) {
        int status_code = esp_http_client_get_status_code(patch_client);
        ESP_LOGI(TAG, "[BOOT PATCH] Setare stare initiala releu status: %d", status_code);
    } else {
        ESP_LOGE(TAG, "[BOOT PATCH] Eroare la setarea starii initiale a releului: %s", esp_err_to_name(err_boot_relay));
    }

    free(patch_resp.data);
    patch_resp.data = NULL;
    patch_resp.len = 0;
    
    s_a_modificat_din_buton = false; 

    s_a_sincronizat_initial = true;

    esp_err_t err = esp_http_client_perform(client);
    if (err == ESP_OK) {
        int status_code = esp_http_client_get_status_code(client);

        if (status_code == 200 && resp.data != NULL && resp.len > 0) {
            cJSON *json_array = cJSON_Parse(resp.data);
            if (json_array != NULL && cJSON_GetArraySize(json_array) > 0) {
                cJSON *first_item = cJSON_GetArrayItem(json_array, 0);
                cJSON *status_item = cJSON_GetObjectItem(first_item, "relay_status");

                if (status_item != NULL) {
                    stare_releu_locala = cJSON_IsTrue(status_item);
                    gpio_set_level(RELAY_COMMAND_PIN, stare_releu_locala ? 0 : 1);
                    ESP_LOGI(TAG, "Stare initiala preluata cu succes: %s", stare_releu_locala ? "ON" : "OFF");
                }
            }
            cJSON_Delete(json_array);
        }
    } else {
        ESP_LOGE(TAG, "Eroare la cererea HTTP GET initiala: %s", esp_err_to_name(err));
    }

    free(resp.data);
    
    s_a_sincronizat_initial = true;

    int consecutive_failures = 0;
    while (1) {
        // Resetăm bufferul de răspuns
        resp.data = NULL;
        resp.len = 0;

        // ── POST telemetrie la 60s ──
        if (++counter_for_post_60s >= 120) {
            counter_for_post_60s = 0;

            // Snapshot date
            portENTER_CRITICAL(&kwh_mux);
            float snap_kwh  = kwh_this_minute;  kwh_this_minute = 0.0f; //
            float snap_v    = voltage_value_for_send;                   //
            float snap_i    = current_value_for_send;                   //
            float snap_p    = active_power_for_send;                    //
            float snap_ap   = apparent_power_for_send;                  //
            float snap_rp   = reactive_power_for_send;                  //
            float snap_pf   = power_factor_for_send;                    //
            float snap_freq = frequency_for_send;                       //
            float snap_thdi = thd_i_for_send;                           //
            float snap_thdv = thd_v_for_send;                           //
            portEXIT_CRITICAL(&kwh_mux);

            static char post_url[256];
            snprintf(post_url, sizeof(post_url), "%s/rest/v1/measurements", SUPABASE_URL);

            static char post_body[512];
            snprintf(post_body, sizeof(post_body),
                "{\"mac_address\":\"%s\",\"voltage\":%.2f,\"current\":%.3f,"
                "\"power\":%.2f,\"apparent_power\":%.2f,\"power_factor\":%.3f,"
                "\"freq\":%.2f,\"thd_i\":%.2f,\"thd_v\":%.2f,\"energy\":%.6f,\"reactive_power\":%.2f}",
                mac_str, snap_v, snap_i, snap_p, snap_ap, snap_pf,
                snap_freq, snap_thdi, snap_thdv, snap_kwh, snap_rp);

            esp_http_client_close(client);

            static http_response_t post_resp = { .data = NULL, .len = 0 };
            esp_http_client_config_t post_config = {
                .url = post_url,
                .method = HTTP_METHOD_POST,
                .event_handler = http_event_handler,
                .user_data = &post_resp,
                .timeout_ms = 5000,
            };
            esp_http_client_handle_t post_client = esp_http_client_init(&post_config);
            esp_http_client_set_header(post_client, "apikey", SUPABASE_KEY);
            esp_http_client_set_header(post_client, "Authorization", "Bearer " SUPABASE_KEY);
            esp_http_client_set_header(post_client, "Content-Type", "application/json");
            esp_http_client_set_header(post_client, "Accept", "application/json");
            esp_http_client_set_header(post_client, "Prefer", "return=minimal");
            esp_http_client_set_post_field(post_client, post_body, strlen(post_body));

            err = esp_http_client_perform(post_client);
            ESP_LOGI(TAG, "[POST 60s] measurements status: %d", esp_http_client_get_status_code(post_client));
            free(post_resp.data);
            esp_http_client_cleanup(post_client);
        }

        // ── PATCH date live la 5s ──
        if (++counter_for_send_5s >= 10) {
            counter_for_send_5s = 0;

            portENTER_CRITICAL(&kwh_mux);
            float snap_kwh  = kwh_this_minute;                          //
            float snap_v    = voltage_value_for_send;                   //
            float snap_i    = current_value_for_send;                   //
            float snap_p    = active_power_for_send;                    //
            float snap_ap   = apparent_power_for_send;                  //
            float snap_rp   = reactive_power_for_send;                  //
            float snap_pf   = power_factor_for_send;                    //
            float snap_freq = frequency_for_send;                       //
            float snap_thdi = thd_i_for_send;                           //
            float snap_thdv = thd_v_for_send;                           //
            portEXIT_CRITICAL(&kwh_mux);


            static char live_body[512];
            snprintf(live_body, sizeof(live_body),
                "{\"voltage\":%.2f,\"current\":%.3f,"
                "\"active_power\":%.2f,\"apparent_power\":%.2f,\"power_factor\":%.3f,"
                "\"freq\":%.2f,\"thd_i\":%.2f,\"thd_v\":%.2f,\"energy\":%.6f,\"reactive_power\":%.2f}",
                snap_v, snap_i, snap_p, snap_ap, snap_pf,
                snap_freq, snap_thdi, snap_thdv, snap_kwh, snap_rp);

            esp_http_client_close(client);
            patch_resp.data = NULL;
            patch_resp.len = 0;
            esp_http_client_set_post_field(patch_client, live_body, strlen(live_body));

            err = esp_http_client_perform(patch_client);
            ESP_LOGI(TAG, "[PATCH 5s] live data status: %d", esp_http_client_get_status_code(patch_client));
            free(patch_resp.data);
            patch_resp.data = NULL;
            patch_resp.len = 0;
        }
        
        if (s_a_modificat_din_buton) {
            ESP_LOGI(TAG, "Buton apasat fizic! Trimitem PATCH catre cloud...");

            static char relay_body[64];
            snprintf(relay_body, sizeof(relay_body), "{\"relay_status\": %s}", stare_releu_locala ? "true" : "false");

            esp_http_client_close(client);
            patch_resp.data = NULL;
            patch_resp.len = 0;
            esp_http_client_set_post_field(patch_client, relay_body, strlen(relay_body));

            err = esp_http_client_perform(patch_client);
            int status_code = esp_http_client_get_status_code(patch_client);
            ESP_LOGW(TAG, "[PATCH buton] Status: %d", status_code);

            if (err == ESP_OK && status_code == 204) {
                ESP_LOGI(TAG, "Stare releu actualizata cu succes!");
                s_a_modificat_din_buton = false;
                consecutive_failures = 0;
            } else {
                ESP_LOGE(TAG, "Eroare PATCH buton (err=%s, status=%d). Reincercam.", esp_err_to_name(err), status_code);
            }

            free(patch_resp.data);
            patch_resp.data = NULL;
            patch_resp.len = 0;
        }
        else {
            esp_http_client_set_method(client, HTTP_METHOD_GET);

            err = esp_http_client_perform(client);

            if (err == ESP_OK && esp_http_client_get_status_code(client) == 200) {
                consecutive_failures = 0;
                if (resp.data != NULL && resp.len > 0) {
                    cJSON *json_array = cJSON_Parse(resp.data);
                    if (json_array != NULL && cJSON_GetArraySize(json_array) > 0) {
                        cJSON *first_item = cJSON_GetArrayItem(json_array, 0);
                        cJSON *status_item = cJSON_GetObjectItem(first_item, "relay_status");

                        if (status_item != NULL) {
                            bool stare_din_cloud = cJSON_IsTrue(status_item);

                            if (stare_din_cloud != stare_releu_locala && !s_a_modificat_din_buton) {
                                ESP_LOGI(TAG, "Comanda primita din aplicatie! Schimb starea releului in %s", stare_din_cloud ? "ON" : "OFF");

                                stare_releu_locala = stare_din_cloud;
                                gpio_set_level(RELAY_COMMAND_PIN, stare_releu_locala ? 0 : 1);
                            }
                        }
                    }
                    cJSON_Delete(json_array);
                }
            } else if (err != ESP_OK) {
                consecutive_failures++;

                if (consecutive_failures >= 3) {
                    ESP_LOGW(TAG, "Resetare completa client HTTP dupa %d esecuri.", consecutive_failures);
                    esp_http_client_cleanup(client);
                    client = esp_http_client_init(&config);
                    esp_http_client_set_header(client, "apikey", SUPABASE_KEY);
                    esp_http_client_set_header(client, "Authorization", "Bearer " SUPABASE_KEY);
                    esp_http_client_set_header(client, "Content-Type", "application/json");
                    esp_http_client_set_header(client, "Accept", "application/json");
                    esp_http_client_set_header(client, "Prefer", "return=minimal");
                    consecutive_failures = 0;
                } else {
                    esp_http_client_close(client);
                }

                int backoff_ms = 2000 * (consecutive_failures + 1);
                if (backoff_ms > 10000) backoff_ms = 10000;
                ESP_LOGW(TAG, "Conexiune GET esuata (%s). Reincercare in %ds...",
                         esp_err_to_name(err), backoff_ms / 1000);

                free(resp.data);
                resp.data = NULL;
                resp.len = 0;
                vTaskDelay(pdMS_TO_TICKS(backoff_ms));
                continue;
            }
        }

        free(resp.data);
        resp.data = NULL;
        resp.len = 0;

        vTaskDelay(pdMS_TO_TICKS(500));
    }
}
