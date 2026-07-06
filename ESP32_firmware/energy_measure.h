#pragma once

#include "esp_adc/adc_cali.h"

// Configurații Pini
#define ZMPT_CHAN          ADC_CHANNEL_8 // GPIO 10
#define SCT_CHAN           ADC_CHANNEL_1 // GPIO 2
#define ADC_UNIT           ADC_UNIT_1
#define ADC_CONV_MODE        ADC_CONV_SINGLE_UNIT_1
#define ADC_ATTEN            ADC_ATTEN_DB_12
#define READ_LEN             1024 
#define ADC_GET_CHANNEL(p)   ((p).type1.channel)

#define TYPE_WAVE_I 0x01
#define TYPE_WAVE_V 0x02
#define TYPE_FFT_I  0x03
#define TYPE_FFT_V  0x04

void init_adc_dma();
void calibrate_offsets_dma();
// float get_real_adc_step(adc_cali_handle_t cali_hdl, float offset_raw);
void adc_read_task(void *args);
void wifi_processing_task(void *pvParameters);
void cloud_telemetry_task(void *pvParameters);