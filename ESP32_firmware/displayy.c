#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/i2c_master.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "ssd1306.h"

static const char *TAG = "DISPLAY";

// Pinii I2C pentru SSD1306
#define I2C_SCL_PIN     4
#define I2C_SDA_PIN     5

// Butoane navigare ecran
#define BUTTON_NEXT     16  // Ecranul urmator
#define BUTTON_PREV     15  // Ecranul anterior
#define NUM_SCREENS     3
#define DEBOUNCE_MS     50

// Variabile externe din energy_measure.c
extern float current_value_for_send;
extern float voltage_value_for_send;
extern float active_power_for_send;
extern float apparent_power_for_send;
extern float reactive_power_for_send;
extern float power_factor_for_send;
extern float frequency_for_send;
extern float thd_i_for_send;
extern float thd_v_for_send;
extern bool ble_mode_active;

static ssd1306_handle_t dev_hdl = NULL;
static int current_screen = 0;

static void display_line(int page, const char *text, bool invert) {
    char buf[17];
    memset(buf, ' ', 16);
    buf[16] = '\0';

    int len = strlen(text);
    if (len > 16) len = 16;
    memcpy(buf, text, len);

    ssd1306_display_text(dev_hdl, page, buf, invert);
}

// Initializare display și butoane
static void init_display(void) {
    ESP_LOGI(TAG, "Initializare magistrala I2C...");
    i2c_master_bus_config_t bus_config = {
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .i2c_port = I2C_NUM_0,
        .scl_io_num = I2C_SCL_PIN,
        .sda_io_num = I2C_SDA_PIN,
        .flags.enable_internal_pullup = true,
        .glitch_ignore_cnt = 7,
    };
    i2c_master_bus_handle_t bus_handle;
    ESP_ERROR_CHECK(i2c_new_master_bus(&bus_config, &bus_handle));

    ESP_LOGI(TAG, "Initializare SSD1306...");
    ssd1306_config_t dev_cfg = I2C_SSD1306_128x64_CONFIG_DEFAULT;
    ssd1306_init(bus_handle, &dev_cfg, &dev_hdl);

    if (dev_hdl == NULL) {
        ESP_LOGE(TAG, "SSD1306 init ESUAT!");
        return;
    }

    ssd1306_clear_display(dev_hdl, false);
    ssd1306_set_contrast(dev_hdl, 0x01);
    ESP_LOGI(TAG, "Display initializat cu succes.");
}

static void init_nav_buttons(void) {
    gpio_config_t io_conf = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_INPUT,
        .pin_bit_mask = (1ULL << BUTTON_NEXT) | (1ULL << BUTTON_PREV),
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
    };
    gpio_config(&io_conf);
}

// ecranele de afisare 

// Ecran 0: Valori principale (U, I, P)
static void draw_screen_main(void) {
    char buf[17];

    display_line(0, "-- MONITOR 1/3 -", true);

    snprintf(buf, sizeof(buf), "U: %.1f V", voltage_value_for_send);
    display_line(2, buf, false);

    snprintf(buf, sizeof(buf), "I: %.3f A", current_value_for_send);
    display_line(4, buf, false);

    snprintf(buf, sizeof(buf), "P: %.1f W", active_power_for_send);
    display_line(6, buf, false);
}

// Ecran 1: Puteri (S, Q, PF)
static void draw_screen_power(void) {
    char buf[17];

    display_line(0, "-- POWER  2/3 --", true);

    snprintf(buf, sizeof(buf), "S: %.1f VA", apparent_power_for_send);
    display_line(2, buf, false);

    snprintf(buf, sizeof(buf), "Q: %.1f VAR", reactive_power_for_send);
    display_line(4, buf, false);

    snprintf(buf, sizeof(buf), "PF: %.3f", power_factor_for_send);
    display_line(6, buf, false);
}

// Ecran 2: Calitate retea (F, THD)
static void draw_screen_quality(void) {
    char buf[17];

    display_line(0, "- QUALITY 3/3 --", true);

    snprintf(buf, sizeof(buf), "F: %.2f Hz", frequency_for_send);
    display_line(2, buf, false);

    snprintf(buf, sizeof(buf), "THD I: %.1f %%", thd_i_for_send);
    display_line(4, buf, false);

    snprintf(buf, sizeof(buf), "THD V: %.1f %%", thd_v_for_send);
    display_line(6, buf, false);
}

// Ecran BLE in cazul în care modul BLE este activ
static void draw_ble_screen(void) {
    display_line(0, "================", true);
    display_line(2, "   BLE  MODE", false);
    display_line(4, "    ACTIVE", false);
    display_line(6, "  Pairing...", false);
}

void display_task(void *pvParameters) {
    init_display();
    init_nav_buttons();

    if (dev_hdl == NULL) {
        ESP_LOGE(TAG, "Display neinitializat, task oprit.");
        vTaskDelete(NULL);
        return;
    }

    bool was_ble_mode = false;
    int last_screen = -1;
    int refresh_counter = 0;

    while (1) {
        bool screen_changed = false;

        if (!ble_mode_active) {
            // Buton NEXT (GPIO 16)
            if (gpio_get_level(BUTTON_NEXT) == 0) {
                vTaskDelay(pdMS_TO_TICKS(DEBOUNCE_MS));
                if (gpio_get_level(BUTTON_NEXT) == 0) {
                    current_screen = (current_screen + 1) % NUM_SCREENS;
                    screen_changed = true;
                    ESP_LOGI(TAG, "Buton NEXT -> Ecran %d", current_screen);
                    while (gpio_get_level(BUTTON_NEXT) == 0) {
                        vTaskDelay(pdMS_TO_TICKS(10));
                    }
                }
            }

            // Buton PREV (GPIO 15)
            if (gpio_get_level(BUTTON_PREV) == 0) {
                vTaskDelay(pdMS_TO_TICKS(DEBOUNCE_MS));
                if (gpio_get_level(BUTTON_PREV) == 0) {
                    current_screen = (current_screen - 1 + NUM_SCREENS) % NUM_SCREENS;
                    screen_changed = true;
                    ESP_LOGI(TAG, "Buton PREV -> Ecran %d", current_screen);
                    while (gpio_get_level(BUTTON_PREV) == 0) {
                        vTaskDelay(pdMS_TO_TICKS(10));
                    }
                }
            }
        }

        // Mod BLE: Override complet al ecranului
        if (ble_mode_active) {
            if (!was_ble_mode) {
                // ssd1306_clear_display(dev_hdl, false);
                was_ble_mode = true;
            }
            draw_ble_screen();
            vTaskDelay(pdMS_TO_TICKS(500));
            continue;
        }

        if (was_ble_mode) {
            was_ble_mode = false;
            last_screen = -1;
        }
        if (current_screen != last_screen || screen_changed) {
            last_screen = current_screen;
            refresh_counter = 10; 
        }
        
        refresh_counter++;
        if (refresh_counter >= 10) {
            refresh_counter = 0;

            switch (current_screen) {
                case 0: draw_screen_main();    break;
                case 1: draw_screen_power();   break;
                case 2: draw_screen_quality(); break;
            }
        }

        vTaskDelay(pdMS_TO_TICKS(50));
    }
}