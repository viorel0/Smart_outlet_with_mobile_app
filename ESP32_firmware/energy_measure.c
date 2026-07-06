#include "energy_measure.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_continuous.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "wifisending.h"
#include <math.h>
#include <stdio.h>

// fft
#include "dsps_fft2r.h"     // Biblioteca FFT pentru ESP32
#include "dsps_wind_hann.h" // Fereastra Hann
#include "esp_wifi.h"
#include "esp_attr.h"

#define WAVEFORM_SAMPLES 800
#define FFT_SAMPLE 2048
#define DECIMATED_LEN 200
#define DECIMATION 4

// Constants
const int samples = 20000;
const float VREF = 3.3f; // 3.3V
const int ADC_RES = 4095;
static float v_offset = 2048.00f;
static float i_offset = 2048.00f;

float voltage_calibration_factor = 558.00f;
float current_calibration_factor = 10.0f;

// Handle-ul pentru ADC DMA
adc_continuous_handle_t handle = NULL;
adc_cali_handle_t cali_handle_zmpt = NULL;
adc_cali_handle_t cali_handle_sct = NULL;

float current_value_for_send = 0.0f;
float voltage_value_for_send = 0.0f;
float active_power_for_send = 0.0f;
float apparent_power_for_send = 0.0f;
float reactive_power_for_send = 0.0f;
float power_factor_for_send = 0.0f;
float frequency_for_send = 0.0f;
float thd_i_for_send = 0.0f;
float thd_v_for_send = 0.0f;

// static float waveform_fft_current[FFT_SAMPLE];
// static float waveform_fft_voltage[FFT_SAMPLE];

EXT_RAM_BSS_ATTR static float waveform_fft_current[FFT_SAMPLE];
EXT_RAM_BSS_ATTR static float waveform_fft_voltage[FFT_SAMPLE];

static float dec_v_global[DECIMATED_LEN];
static float dec_i_global[DECIMATED_LEN];

static float fft_input[FFT_SAMPLE * 2]__attribute__((aligned(16)));
EXT_RAM_BSS_ATTR static float window_fft[FFT_SAMPLE]; 

float val_fs = 20000.0f;

static float ffti[128];
static float fftv[128];

float value_freq = 0;

float thd_i = 0.0f;
float thd_v = 0.0f;

void init_adc_dma() {
  adc_continuous_handle_cfg_t adc_config = {
      .max_store_buf_size = 4096,  // Buffer-ul intern
      .conv_frame_size = READ_LEN, // Dimensiunea unui "pachet" de date
  };
  ESP_ERROR_CHECK(adc_continuous_new_handle(&adc_config, &handle));

  adc_continuous_config_t dig_cfg = {
      .sample_freq_hz =
          40 * 1000, // 20kHz - foarte rapid pentru 50Hz, 40khz/2 fiindca sunt
                     // doua canale, deci 20khz de fapt pe canal
      .conv_mode = ADC_CONV_MODE,
      .format = ADC_DIGI_OUTPUT_FORMAT_TYPE2,
  };

  // Definim pinii
  adc_digi_pattern_config_t adc_pattern[2] = {0};
  adc_pattern[0].atten = ADC_ATTEN;
  adc_pattern[0].channel = ZMPT_CHAN;
  adc_pattern[0].unit = ADC_UNIT;
  adc_pattern[0].bit_width = SOC_ADC_DIGI_MAX_BITWIDTH;

  adc_pattern[1].atten = ADC_ATTEN;
  adc_pattern[1].channel = SCT_CHAN;
  adc_pattern[1].unit = ADC_UNIT;
  adc_pattern[1].bit_width = SOC_ADC_DIGI_MAX_BITWIDTH;

  dig_cfg.pattern_num = 2;
  dig_cfg.adc_pattern = adc_pattern;

  ESP_ERROR_CHECK(adc_continuous_config(handle, &dig_cfg));

  adc_cali_curve_fitting_config_t cali_config_zmpt = {
      .unit_id  = ADC_UNIT_1,
      .chan     = ZMPT_CHAN,
      .atten    = ADC_ATTEN,
      .bitwidth = SOC_ADC_DIGI_MAX_BITWIDTH,
  };
  ESP_ERROR_CHECK(adc_cali_create_scheme_curve_fitting(&cali_config_zmpt, &cali_handle_zmpt));

  adc_cali_curve_fitting_config_t cali_config_sct = {
      .unit_id  = ADC_UNIT_1,
      .chan     = SCT_CHAN, 
      .atten    = ADC_ATTEN,
      .bitwidth = SOC_ADC_DIGI_MAX_BITWIDTH,
  };
  ESP_ERROR_CHECK(adc_cali_create_scheme_curve_fitting(&cali_config_sct, &cali_handle_sct));
}

void calibrate_offsets_dma() {
  static uint8_t result[READ_LEN] = {0};
  uint32_t ret_num = 0;

  double v_sum = 0;
  double i_sum = 0;
  int samples_collected = 0;
  int samples_v = 0;
  const int target_samples = 20000;

  ESP_ERROR_CHECK(adc_continuous_start(handle));
  
  while (samples_collected < target_samples) {
    esp_err_t ret = adc_continuous_read(handle, result, READ_LEN, &ret_num, 100);
    if (ret == ESP_OK) {
      for (int i = 0; i < ret_num; i += SOC_ADC_DIGI_RESULT_BYTES) {
        adc_digi_output_data_t *p = (adc_digi_output_data_t *)&result[i];
        uint32_t chan = p->type2.channel;
        uint32_t raw_val = p->type2.data;

        if (chan == ZMPT_CHAN) {
          v_sum += raw_val;
          samples_v++;
        } else if (chan == SCT_CHAN) {
          i_sum += raw_val;
          samples_collected++;
        }
      }
    }
  }

  // Offset-urile în RAW
  v_offset = (float)v_sum / samples_v;
  i_offset = (float)i_sum / samples_collected;

  printf("v_offset=%.2f RAW, i_offset=%.2f RAW\n", v_offset, i_offset);
  printf("samples_v=%d, samples_collected=%d\n", samples_v, samples_collected);

  ESP_ERROR_CHECK(adc_continuous_stop(handle));
}

float get_real_adc_step(adc_cali_handle_t cali_hdl, float offset_raw) {
  if (cali_hdl == NULL) {
    return 3.3f / 4095.0f;
  }
  
  int mv_low, mv_high;
  adc_cali_raw_to_voltage(cali_hdl, (int)offset_raw, &mv_low);
  adc_cali_raw_to_voltage(cali_hdl, (int)offset_raw + 1000, &mv_high);

  return (float)(mv_high - mv_low) / 1000.0f / 1000.0f;
}

void init_fft_and_window() {
  esp_err_t ret = dsps_fft2r_init_fc32(NULL, CONFIG_DSP_MAX_FFT_SIZE);
  if (ret != ESP_OK) {
    ESP_LOGE("DSP", "Nu s-a putut initializa FFT");
  }
  dsps_wind_hann_f32(window_fft, FFT_SAMPLE);
}

float calculate_thd_internal(const float *mag) {
  // 1. Căutăm fundamentala (peak search între bin 3 și 7)
  int fund_idx = (int)(50 * 2048) / val_fs;
  // printf("val_fs: %f\n", val_fs);
  float max_v = 0;
  for (int i = 3; i <= 7; i++) {
    if (mag[i] > max_v) {
      max_v = mag[i];
      fund_idx = i;
    }
  }

  if (mag[fund_idx] < 0.001f){
    return 0.0f;
  }
  float sum_harmonics_sq = 0;

  for (int n = 2; n <= 40; n++) {
    int bin = fund_idx * n;
    if (bin < 2048) {
      sum_harmonics_sq += (mag[bin] * mag[bin]);
    }
  }

  //returnăm procentul THD
  return (sqrtf(sum_harmonics_sq) / mag[fund_idx]) * 100.0f;
}

void process_fft_and_thd() {
  float *magnitude = (float *)fft_input;
  for (int i = 0; i < FFT_SAMPLE; i++) {
    fft_input[i * 2 + 0] =
        waveform_fft_current[i] * window_fft[i]; // Aplicăm fereastra Hann
    fft_input[i * 2 + 1] = 0.0f;
  }
  dsps_fft2r_fc32(fft_input, FFT_SAMPLE);   
  dsps_bit_rev_fc32(fft_input, FFT_SAMPLE);

  for (int i = 0; i < FFT_SAMPLE / 2; i++) {
    float re = fft_input[i * 2];
    float im = fft_input[i * 2 + 1];
    magnitude[i] = (sqrtf(re * re + im * im) / FFT_SAMPLE); 
  
  }
  thd_i = calculate_thd_internal(magnitude);

  memcpy(ffti, magnitude, 128 * sizeof(float));
 
  for (int i = 0; i < FFT_SAMPLE; i++) {
    fft_input[i * 2 + 0] =
        waveform_fft_voltage[i] * window_fft[i];
    fft_input[i * 2 + 1] = 0.0f;
  }
  dsps_fft2r_fc32(fft_input, FFT_SAMPLE);
  dsps_bit_rev_fc32(fft_input, FFT_SAMPLE);

  for (int i = 0; i < FFT_SAMPLE / 2; i++) {
    float re = fft_input[i * 2];
    float im = fft_input[i * 2 + 1];
    magnitude[i] = (sqrtf(re * re + im * im) / FFT_SAMPLE);
  }
  thd_v = calculate_thd_internal(magnitude);

  memcpy(fftv, magnitude, 128 * sizeof(float));
  
}

void get_wifi_strength() {
  wifi_ap_record_t ap_info;
  if (esp_wifi_sta_get_ap_info(&ap_info) == ESP_OK) {
    int8_t rssi = ap_info.rssi;
    printf("Wi-Fi RSSI: %d dBm\n", rssi);
  }
}

float calculate_grid_frequency(float *waveform, int num_samples, float fs, int *trigger_index) {
  float hysteresis = 15.0f; // Prag de siguranță de 15 Volți
  int state = 0; // 0 sub prag, 1 peste prag

  float crossing_times[32];
  int cross_count = 0;

  for (int i = 1; i < num_samples; i++) {
    if (state == 0) {
      // Așteptăm să scadă bine în negativ ca să armăm detectorul
      if (waveform[i] < -hysteresis) {
        state = 1;
      }
    } else if (state == 1) {
      // Așteptăm să urce peste valoare de hysteresis
      if (waveform[i] > hysteresis) {

        // dupa ce stim sigur ca a trecut cautam exact momentul cand a trecut prin zero
        int z = i;
        while (z > 0 && waveform[z] > 0.0f) {
          z--;
        }

        float y1 = waveform[z];
        float y2 = waveform[z + 1];

        // interpolare liniară pentru precizie
        float fraction = 0.0f;
        if (y2 - y1 > 0.001f) {
          fraction = (0.0f - y1) / (y2 - y1);
        }

        crossing_times[cross_count++] = (float)z + fraction;
        state = 0; // Resetăm pentru următorul ciclu

        if (cross_count >= 5)
          break;
      }
    }
  }
  if (cross_count < 2)
    return 0.0f;

  // Limita de perioadă: 45-55 Hz
  float min_period = fs / 55.0f; // ~365 eșantioane
  float max_period = fs / 45.0f; // ~447 eșantioane

  float valid_period_sum = 0.0f;
  int valid_count = 0;
  for (int i = 1; i < cross_count; i++) {
    float period = crossing_times[i] - crossing_times[i - 1];
    if (period >= min_period && period <= max_period) {
      valid_period_sum += period;
      valid_count++;
    }
  }
  if (valid_count == 0)
    return 0.0f;
  float avg_period_samples = valid_period_sum / valid_count;

  if (trigger_index != NULL && cross_count > 0) {
    *trigger_index = (int)crossing_times[0];  // Primul zero crossing
  }

  return fs / avg_period_samples;
}

float kwh_this_minute = 0.0f;
portMUX_TYPE kwh_mux = portMUX_INITIALIZER_UNLOCKED; 
static int64_t last_energy_time = 0;

void energy_in_one_minute(float active_power) {
  int64_t current_time = esp_timer_get_time();
  
  if (last_energy_time == 0) {
    last_energy_time = current_time;
  } else {
    float dt = (float)(current_time - last_energy_time) / 1000000.0f;
    last_energy_time = current_time;

    float p_watts = (active_power > 0.0f) ? active_power : 0.0f;

    float delta_kwh = (p_watts * dt) / (3600.0f * 1000.0f);

    portENTER_CRITICAL(&kwh_mux);
    kwh_this_minute += delta_kwh;
    portEXIT_CRITICAL(&kwh_mux);
  }
}

static int64_t start_time = 0;
extern TaskHandle_t wifi_proc_task_hdl;
extern TaskHandle_t cloud_telemetry_task_hdl;

void adc_read_task(void *args) {
  uint8_t result[READ_LEN] = {0};
  uint32_t ret_num = 0;
  init_fft_and_window(); 
  // ESP_ERROR_CHECK(adc_continuous_flush_pool(handle)); 
  ESP_ERROR_CHECK(adc_continuous_start(handle));
  double sum_v_sq = 0;
  double sum_i_sq = 0;
  double sum_v = 0;
  double sum_i = 0;
  double sum_p = 0;
  // float last_v = 0;
  
  static float v_history[64] = {0.0f};
  static int v_hist_idx = 0;
  #define PHASE_DELAY 21
  int sample_count = 0;
  // float max_current = 0;
  // float max_voltage = 0;
  // float display_v_inst = 0;
  // float display_i_inst = 0;
  // static int skip_counter = 0;
  // static int fft_timer = 0;
  // static int debug_count = 0;

  // float maxval_v = -9999.9f;
  // float minval_v = 9999.9f;
  // float maxval_i = -9999.9f;
  // float minval_i = 9999.9f;

  float v_step = get_real_adc_step(cali_handle_zmpt, v_offset);
  float to_voltage = v_step * voltage_calibration_factor;
  float i_step = get_real_adc_step(cali_handle_sct, i_offset);
  float to_ampere = i_step * current_calibration_factor;
  printf("Pas real ADC pentru tensiune: %.6f V/step\n", v_step);
  printf("Pas real ADC pentru curent: %.6f A/step\n", i_step);

  {
  static uint8_t result_test[READ_LEN];
  uint32_t ret_num_test = 0;
  int cnt_v = 0, cnt_i = 0;
  int64_t t_start = esp_timer_get_time();

  // Colectam 2 secunde de date
  while ((esp_timer_get_time() - t_start) < 2000000) {
    if (adc_continuous_read(handle, result_test, READ_LEN, &ret_num_test,
                            100) == ESP_OK) {
      for (int i = 0; i < ret_num_test; i += SOC_ADC_DIGI_RESULT_BYTES) {
        adc_digi_output_data_t *p = (adc_digi_output_data_t *)&result_test[i];
        if (p->type2.channel == ZMPT_CHAN)
          cnt_v++;
        else if (p->type2.channel == SCT_CHAN)
          cnt_i++;
      }
    }
  }
  val_fs = (cnt_v + cnt_i) / 4.0f;
  printf("=== FS REAL ===\n");
  printf("Canal V (GPIO10): %d esantioane in 2s → Fs = %.1f Hz\n", cnt_v,
          cnt_v / 2.0f);
  printf("Canal I (GPIO2): %d esantioane in 2s → Fs = %.1f Hz\n", cnt_i,
          cnt_i / 2.0f);
  printf("Total: %d → Fs total = %.1f Hz\n", cnt_v + cnt_i,
          (cnt_v + cnt_i) / 2.0f);
  printf("===============\n");
  }

  while (1) {
    
    esp_err_t ret = adc_continuous_read(handle, result, READ_LEN, &ret_num, 100);
  
    if (ret == ESP_OK) {
      for (int i = 0; i < ret_num; i += SOC_ADC_DIGI_RESULT_BYTES) {

        adc_digi_output_data_t *p = (adc_digi_output_data_t *)&result[i];

        uint32_t chan = p->type2.channel;
        uint32_t raw_val = p->type2.data; 

        if (chan == ZMPT_CHAN) { // Tensiune
          // float v_inst_raw = (float)raw_val - v_offset;
          // float v_calculated = v_inst_raw * to_voltage;

          // if (sample_count < FFT_SAMPLE) {
          //   waveform_fft_voltage[sample_count] = v_calculated;
          // }
          // sum_v_sq += (double)v_calculated * v_calculated;
          // sum_v += (double)v_calculated;
          // last_v = v_inst_raw;

          float x = ((float)raw_val - v_offset) * v_step;
          // if (raw_val > maxval_v) {
          //   maxval_v = raw_val;
          // }
          // if (raw_val < minval_v) {
          //   minval_v = raw_val;
          // }
          // ESP_LOGI("S", "raw_val: %.2f, v_offset: %.2f, v_step: %.6f, x: %.4f\n", (float)raw_val, v_offset, v_step, x);

          // const float poly_a = 0.00000412f; 
          // const float poly_b = -0.000857f; 
          // const float poly_c = 2.675f;  
          // const float poly_d = -3.198f;      

          const float poly_a = 0.0000015489f;
          const float poly_b = -0.0003221f;
          const float poly_c = 1.00582f;
          // const float poly_d = -1.84473f;
          const float poly_d = 0.00f;

          float v_inst = ((poly_a * x + poly_b) * x + poly_c) * x + poly_d;
          // printf("v_inst: %.2f \n", v_inst);
          float v_inst_calibrat = v_inst * voltage_calibration_factor;
          
          // float v_inst_calibrat = v_calculated;
          
          v_history[v_hist_idx] = v_inst_calibrat;
          v_hist_idx = (v_hist_idx + 1) % 64;
          
          if (sample_count < FFT_SAMPLE) {
              waveform_fft_voltage[sample_count] = v_inst_calibrat;
              // printf("%.2f ", v_inst_calibrat);
          }
          
          sum_v_sq += (double)v_inst_calibrat * v_inst_calibrat;
          sum_v += (double)v_inst_calibrat;

        } else if (chan == SCT_CHAN) {
          float i_inst_raw = ((float)raw_val - i_offset);
          //  if (raw_val > maxval_i) {
          //   maxval_i = raw_val;
          // }
          // if (raw_val < minval_i) {
          //   minval_i = raw_val;
          // }
          float i_calculated = i_inst_raw * to_ampere;
          // ESP_LOGI("S", " i_inst_raw %.2f, raw_val %.2f ,i_offset %.2f", i_inst_raw, (float)raw_val, i_offset);
          if (sample_count < FFT_SAMPLE) {
            waveform_fft_current[sample_count] = i_calculated;
          }
          sum_i_sq += (double)i_calculated * i_calculated;
          sum_i += (double)i_calculated;
          
          int delayed_idx = (v_hist_idx - 1 - PHASE_DELAY + 64) % 64;
          float delayed_v = v_history[delayed_idx];
          sum_p += (double)delayed_v * i_calculated;
          
          sample_count++;

          if (sample_count >= samples) {
            break;
          }
        }
      }
      
      if (sample_count >= samples) {
          
        float mean_v = sum_v / sample_count;
        float mean_i = sum_i / sample_count;
        // printf("Mean V: %.2f V, Mean I: %.3f A\n", mean_v, mean_i);
        
        float mean_sq_v = sum_v_sq / sample_count;
        float mean_sq_i = sum_i_sq / sample_count;
        float mean_p = sum_p / sample_count;
          
        // float minim = 0.0f;
        // float maxim = 0.0f;

        for (int k = 0; k < FFT_SAMPLE; k++) {
          // if (waveform_fft_voltage[k] < minim) {
          //   minim = waveform_fft_voltage[k];
          // }
          // if (waveform_fft_voltage[k] > maxim) {
          //   maxim = waveform_fft_voltage[k];
          // }
          waveform_fft_voltage[k] -= mean_v;
          waveform_fft_current[k] -= mean_i; 
        }
          
        // printf("Min V: %.2f V, Max V: %.2f V\n", minim, maxim);
        
        float v_rms_raw = sqrtf(fabsf(mean_sq_v - (mean_v * mean_v)));
        float i_rms_raw = sqrtf(fabsf(mean_sq_i - (mean_i * mean_i)));
        
        float p_raw_clean = mean_p - (mean_v * mean_i);

        float ac_voltage = v_rms_raw;
        float ac_current = i_rms_raw/3.0f;
        float active_power = p_raw_clean/3.0f;
          
        if (ac_voltage < 25.0f) {
          ac_voltage = 0.0f;
        }
        if (ac_current < 0.04f) {
          ac_current = 0.0f;
        }
        if (ac_current == 0.00f) {
          active_power = 0.0f;
        }
        if (ac_voltage == 0.00f) {
          active_power = 0.0f;
        }
          
        energy_in_one_minute(active_power);
          
        // Puterea aparentă și reactivă, factorul de putere
        float apparent_power = ac_voltage * ac_current;
        float reactive_power = sqrtf(fabsf(apparent_power * apparent_power - active_power * active_power));
        float power_factor = (apparent_power > 0.0f) ? (active_power / apparent_power) : 0.0f;
        
        int crossing_index = 0;
        float freq = calculate_grid_frequency(waveform_fft_voltage, FFT_SAMPLE, val_fs, &crossing_index);
        
        for (int j = 0; j < DECIMATED_LEN; j++) {
          float val_v_bruta = waveform_fft_voltage[crossing_index + j * DECIMATION];
          float val_i_bruta = waveform_fft_current[crossing_index + j * DECIMATION];
          
          if (j > 0) {
            // Aplicăm filtru
            dec_v_global[j] = (dec_v_global[j - 1] * 0.75f) + (val_v_bruta * 0.25f);
            dec_i_global[j] = (dec_i_global[j - 1] * 0.70f) + (val_i_bruta * 0.30f);
          } else {
            dec_v_global[j] = val_v_bruta;
            dec_i_global[j] = val_i_bruta;
          }
        }

        // for (int j = 0; j < DECIMATED_LEN; j++) {
        //   dec_v_global[j] = waveform_fft_voltage[crossing_index + j * DECIMATION];
        //   dec_i_global[j] = waveform_fft_current[crossing_index + j * DECIMATION];
        // }
        
        process_fft_and_thd();

        if (ac_current == 0.00f) {
          thd_i = 0.0f;
        }
        if (ac_voltage == 0.00f) {
          thd_v = 0.0f;
        }

        portENTER_CRITICAL(&kwh_mux);
        frequency_for_send        = freq;
        voltage_value_for_send    = ac_voltage;
        current_value_for_send    = ac_current;
        active_power_for_send     = active_power;
        apparent_power_for_send   = apparent_power;
        reactive_power_for_send   = reactive_power;
        thd_i_for_send            = thd_i;
        thd_v_for_send            = thd_v;
        power_factor_for_send     = power_factor;
        portEXIT_CRITICAL(&kwh_mux);

        printf("Frecv: %.2f Hz | V: %.2f V | I: %.3f A | P: %.2f W | APP: %.2f VA | RP: %.2f VAR | THD I: %.2f | THD V: %.2f | PF: %.2f\n",
            freq, ac_voltage, ac_current, active_power, apparent_power, reactive_power, thd_i, thd_v, power_factor);
        if (wifi_proc_task_hdl != NULL) {
          xTaskNotifyGive(wifi_proc_task_hdl);
        }
          
        sum_v_sq = 0;
        sum_i_sq = 0;
        sum_p = 0;
        sum_v = 0;
        sum_i = 0;
        sample_count = 0;
      }
    }
  }
}

void wifi_processing_task(void *pvParameters) {
  // static int skip_counter = 0;
  while (1) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

    // if (++skip_counter >= 3) {
    send_waveform_udp(dec_v_global, dec_i_global, fftv, ffti);
      // skip_counter = 0;
    // }
    // vTaskDelay(pdMS_TO_TICKS(10));
  }
}
