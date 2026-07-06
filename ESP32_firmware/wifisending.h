#pragma once

void wifi_init_sta(void);
void button_control_task(void *pvParameters);
void send_waveform_udp(float *wavev, float *wavei, float *wavefftv,
                       float *waveffti);
void udp_socket_init(void);
void udp_socket_deinit(void);
void relay_button_task(void *pvParameters);
void cloud_sync_task(void *pvParameters);

extern volatile bool udp_enabled;