#include "acfrequency.h"
#include "displayy.h"
#include "energy_measure.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"
#include "wifisending.h"
#include "esp_bt.h"
#include "freertos/event_groups.h"
#include "esp_task_wdt.h"
#include "bluenimble.h"

TaskHandle_t wifi_proc_task_hdl = NULL;
TaskHandle_t cloud_telemetry_task_hdl = NULL;
TaskHandle_t cloud_sync_task_hdl = NULL;
EventGroupHandle_t wifi_event_group;

void app_main(void) {
  esp_task_wdt_config_t wdt_config = {
      .timeout_ms = 15000,
      .idle_core_mask = (1 << 0) | (1 << 1),
      .trigger_panic = false,
  };
  esp_task_wdt_reconfigure(&wdt_config);
  
  wifi_event_group = xEventGroupCreate();

  
  esp_err_t ret = nvs_flash_init();
  if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
    ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
      ESP_ERROR_CHECK(nvs_flash_erase());
      ret = nvs_flash_init();
    }
  ESP_ERROR_CHECK(ret);

  ESP_ERROR_CHECK(esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT));
  ESP_LOGI(NULL,"[SYSTEM] Memoria de Bluetooth a fost eliberată în avans.\n");
  
  wifi_init_sta();
  
  init_adc_dma();
  
  calibrate_offsets_dma();

  xTaskCreatePinnedToCore(adc_read_task, "ADC Read Task", 8192, NULL, 10, NULL,
                          1);

  xTaskCreatePinnedToCore(button_control_task, "buttonresettask", 2048, NULL, 2,
                          NULL, 0);

  xTaskCreatePinnedToCore(display_task, "display_task", 4096, NULL, 2, NULL, 0);

  xTaskCreatePinnedToCore(relay_button_task, "relay_button_task", 2048, NULL, 2,
                          NULL, 0);
    
}