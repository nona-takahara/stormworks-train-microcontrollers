# --- Three-digit IDs first (n500+) ---

# --- n634 rolling_stock_ch2_read ---
s/\bn634_out\b/rolling_stock_ch2_read_out/g
s/\bn634\b/rolling_stock_ch2_read/g

# --- n633 atc_reset_pulse (outputs to port) ---
s/\bn633\b/atc_reset_pulse/g

# --- n629 ext_cmd_ch32_read ---
s/\bn629_out\b/ext_cmd_ch32_read_out/g
s/\bn629\b/ext_cmd_ch32_read/g

# --- n628 ext_cmd_ch10_read ---
s/\bn628_out\b/ext_cmd_ch10_read_out/g
s/\bn628\b/ext_cmd_ch10_read/g

# --- n627 ext_cmd_ch1_read ---
s/\bn627_out\b/ext_cmd_ch1_read_out/g
s/\bn627\b/ext_cmd_ch1_read/g

# --- n626 const_false_bool ---
s/\bn626_out\b/const_false_bool_out/g
s/\bn626\b/const_false_bool/g

# --- n625 const_true_not ---
s/\bn625_out\b/const_true_not_out/g
s/\bn625\b/const_true_not/g

# --- n624 simif_rx_ch1_bool_read ---
s/\bn624_out\b/simif_rx_ch1_bool_read_out/g
s/\bn624\b/simif_rx_ch1_bool_read/g

# --- n623 simif_rx_ch2_num_read ---
s/\bn623_out\b/simif_rx_ch2_num_read_out/g
s/\bn623\b/simif_rx_ch2_num_read/g

# --- n622 simif_rx_ch1_num_read ---
s/\bn622_out\b/simif_rx_ch1_num_read_out/g
s/\bn622\b/simif_rx_ch1_num_read/g

# --- n619 handle_output_type_prop ---
s/\bn619_out\b/handle_output_type_prop_out/g
s/\bn619\b/handle_output_type_prop/g

# --- n618 handle_output_sw (outputs to port) ---
s/\bn618\b/handle_output_sw/g

# --- n617 drive_express_yama_read (outputs to port) ---
s/\bn617\b/drive_express_yama_read/g

# --- n616 high_beam_not (outputs to port) ---
s/\bn616\b/high_beam_not/g

# --- n603 physics_speed_read ---
s/\bn603_out\b/physics_speed_read_out/g
s/\bn603\b/physics_speed_read/g

# --- n596 ds_ch4_bool_read ---
s/\bn596_out\b/ds_ch4_bool_read_out/g
s/\bn596\b/ds_ch4_bool_read/g

# --- n595 conductor_and_speed ---
s/\bn595_out\b/conductor_and_speed_out/g
s/\bn595\b/conductor_and_speed/g

# --- n594 conductor_ch21_and ---
s/\bn594_out\b/conductor_ch21_and_out/g
s/\bn594\b/conductor_ch21_and/g

# --- n593 conductor_ch20_and ---
s/\bn593_out\b/conductor_ch20_and_out/g
s/\bn593\b/conductor_ch20_and/g

# --- n592 conductor_ch19_and ---
s/\bn592_out\b/conductor_ch19_and_out/g
s/\bn592\b/conductor_ch19_and/g

# --- n591 simif_rx_ch5_bool_read ---
s/\bn591_out\b/simif_rx_ch5_bool_read_out/g
s/\bn591\b/simif_rx_ch5_bool_read/g

# --- n590 simif_active_or ---
s/\bn590_out\b/simif_active_or_out/g
s/\bn590\b/simif_active_or/g

# --- n589 ds_ch3_bool_read ---
s/\bn589_out\b/ds_ch3_bool_read_out/g
s/\bn589\b/ds_ch3_bool_read/g

# --- n588 ds_back_enable ---
s/\bn588_out\b/ds_back_enable_out/g
s/\bn588\b/ds_back_enable/g

# --- n587 ds_front_enable ---
s/\bn587_out\b/ds_front_enable_out/g
s/\bn587\b/ds_front_enable/g

# --- n580 settings_ch10_read ---
s/\bn580_out\b/settings_ch10_read_out/g
s/\bn580\b/settings_ch10_read/g

# --- n579 ds_inhibit_not ---
s/\bn579_out\b/ds_inhibit_not_out/g
s/\bn579\b/ds_inhibit_not/g

# --- n578 ds_ch2_bool_read ---
s/\bn578_out\b/ds_ch2_bool_read_out/g
s/\bn578\b/ds_ch2_bool_read/g

# --- n577 ds_gate_and ---
s/\bn577_out\b/ds_gate_and_out/g
s/\bn577\b/ds_gate_and/g

# --- n575 express_umi_direct_read (outputs to port) ---
s/\bn575\b/express_umi_direct_read/g

# --- n570 settings_ch6_read ---
s/\bn570_out\b/settings_ch6_read_out/g
s/\bn570\b/settings_ch6_read/g

# --- n569 drive_headlight_read ---
s/\bn569_out\b/drive_headlight_read_out/g
s/\bn569\b/drive_headlight_read/g

# --- n568 drive_ch1_read ---
s/\bn568_out\b/drive_ch1_read_out/g
s/\bn568\b/drive_ch1_read/g

# --- n567 monitor_num_write (outputs to port) ---
s/\bn567\b/monitor_num_write/g

# --- n566 monitor_bool_write ---
s/\bn566_out\b/monitor_bool_write_out/g
s/\bn566\b/monitor_bool_write/g

# --- n556 ds_ch1_num_read ---
s/\bn556_out\b/ds_ch1_num_read_out/g
s/\bn556\b/ds_ch1_num_read/g

# --- n536 status_num ---
s/\bn536_out\b/status_num_out/g
s/\bn536\b/status_num/g

# --- n531 drive_ch21_read ---
s/\bn531_out\b/drive_ch21_read_out/g
s/\bn531\b/drive_ch21_read/g

# --- n530 drive_ch20_read ---
s/\bn530_out\b/drive_ch20_read_out/g
s/\bn530\b/drive_ch20_read/g

# --- n529 drive_ch19_read ---
s/\bn529_out\b/drive_ch19_read_out/g
s/\bn529\b/drive_ch19_read/g

# --- n525 eb_flag_func ---
s/\bn525_out\b/eb_flag_func_out/g
s/\bn525\b/eb_flag_func/g

# --- n509 drive_ch14_not ---
s/\bn509_out\b/drive_ch14_not_out/g
s/\bn509\b/drive_ch14_not/g

# --- n508 drive_ch14_read ---
s/\bn508_out\b/drive_ch14_read_out/g
s/\bn508\b/drive_ch14_read/g

# --- n506 settings_ch15_read ---
s/\bn506_out\b/settings_ch15_read_out/g
s/\bn506\b/settings_ch15_read/g

# --- n505 formation_not_fwd_delta ---
s/\bn505_out\b/formation_not_fwd_delta_out/g
s/\bn505\b/formation_not_fwd_delta/g

# --- n504 formation_fwd_delta_thresh ---
s/\bn504_out\b/formation_fwd_delta_thresh_out/g
s/\bn504\b/formation_fwd_delta_thresh/g

# --- n503 formation_delta ---
s/\bn503_out\b/formation_delta_out/g
s/\bn503\b/formation_delta/g

# --- Three-digit IDs (n400+) ---

# --- n494 settings_ch17_read ---
s/\bn494_out\b/settings_ch17_read_out/g
s/\bn494\b/settings_ch17_read/g

# --- n493 settings_ch16_read ---
s/\bn493_out\b/settings_ch16_read_out/g
s/\bn493\b/settings_ch16_read/g

# --- n492 settings_ch12_key_and ---
s/\bn492_out\b/settings_ch12_key_and_out/g
s/\bn492\b/settings_ch12_key_and/g

# --- n491 settings_ch12_read ---
s/\bn491_out\b/settings_ch12_read_out/g
s/\bn491\b/settings_ch12_read/g

# --- n490 settings_ch3_read ---
s/\bn490_out\b/settings_ch3_read_out/g
s/\bn490\b/settings_ch3_read/g

# --- n489 settings_ch4_read ---
s/\bn489_out\b/settings_ch4_read_out/g
s/\bn489\b/settings_ch4_read/g

# --- n488 status_bool_write ---
s/\bn488_out\b/status_bool_write_out/g
s/\bn488\b/status_bool_write/g

# --- n483 eb_and_fwd ---
s/\bn483_out\b/eb_and_fwd_out/g
s/\bn483\b/eb_and_fwd/g

# --- n479 mascon_key_and_fwd ---
s/\bn479_out\b/mascon_key_and_fwd_out/g
s/\bn479\b/mascon_key_and_fwd/g

# --- n478 settings_ch7_fall_pulse ---
s/\bn478_out\b/settings_ch7_fall_pulse_out/g
s/\bn478\b/settings_ch7_fall_pulse/g

# --- n477 settings_ch7_rise_pulse ---
s/\bn477_out\b/settings_ch7_rise_pulse_out/g
s/\bn477\b/settings_ch7_rise_pulse/g

# --- n476 reverser_bck_thresh ---
s/\bn476_out\b/reverser_bck_thresh_out/g
s/\bn476\b/reverser_bck_thresh/g

# --- n475 reverser_fwd_thresh ---
s/\bn475_out\b/reverser_fwd_thresh_out/g
s/\bn475\b/reverser_fwd_thresh/g

# --- n473 formation_back_flag ---
s/\bn473_out\b/formation_back_flag_out/g
s/\bn473\b/formation_back_flag/g

# --- n472 crew_warning_fall_pulse ---
s/\bn472_out\b/crew_warning_fall_pulse_out/g
s/\bn472\b/crew_warning_fall_pulse/g

# --- n471 crew_warning_rise_pulse ---
s/\bn471_out\b/crew_warning_rise_pulse_out/g
s/\bn471\b/crew_warning_rise_pulse/g

# --- n470 settings_ch8_fall_pulse ---
s/\bn470_out\b/settings_ch8_fall_pulse_out/g
s/\bn470\b/settings_ch8_fall_pulse/g

# --- n469 settings_ch8_rise_pulse ---
s/\bn469_out\b/settings_ch8_rise_pulse_out/g
s/\bn469\b/settings_ch8_rise_pulse/g

# --- n456 tx_bool_write (outputs to port) ---
s/\bn456\b/tx_bool_write/g

# --- n448 tx_num_write ---
s/\bn448_out\b/tx_num_write_out/g
s/\bn448\b/tx_num_write/g

# --- Three-digit IDs (n300+) ---

# --- n398 speed_near_zero_thresh ---
s/\bn398_out\b/speed_near_zero_thresh_out/g
s/\bn398\b/speed_near_zero_thresh/g

# --- n397 conductor_speed_ok_or ---
s/\bn397_out\b/conductor_speed_ok_or_out/g
s/\bn397\b/conductor_speed_ok_or/g

# --- n396 settings_conductor_override ---
s/\bn396_out\b/settings_conductor_override_out/g
s/\bn396\b/settings_conductor_override/g

# --- n395 simif_not_active ---
s/\bn395_out\b/simif_not_active_out/g
s/\bn395\b/simif_not_active/g

# --- n394 limit_enable_or ---
s/\bn394_out\b/limit_enable_or_out/g
s/\bn394\b/limit_enable_or/g

# --- n393 simif_rx_ch4_bool_read ---
s/\bn393_out\b/simif_rx_ch4_bool_read_out/g
s/\bn393\b/simif_rx_ch4_bool_read/g

# --- n392 speed_limit_default_sw ---
s/\bn392_out\b/speed_limit_default_sw_out/g
s/\bn392\b/speed_limit_default_sw/g

# --- n375 drive_tail_on_read ---
s/\bn375_out\b/drive_tail_on_read_out/g
s/\bn375\b/drive_tail_on_read/g

# --- n374 formation_bck_thresh_tail ---
s/\bn374_out\b/formation_bck_thresh_tail_out/g
s/\bn374\b/formation_bck_thresh_tail/g

# --- n373 tail_sign_or (outputs to port) ---
s/\bn373\b/tail_sign_or/g

# --- n372 drive_express_umi_sign_read ---
s/\bn372_out\b/drive_express_umi_sign_read_out/g
s/\bn372\b/drive_express_umi_sign_read/g

# --- n371 express_umi_rise_pulse ---
s/\bn371_out\b/express_umi_rise_pulse_out/g
s/\bn371\b/express_umi_rise_pulse/g

# --- n370 express_umi_fall_pulse ---
s/\bn370_out\b/express_umi_fall_pulse_out/g
s/\bn370\b/express_umi_fall_pulse/g

# --- n369 formation_fwd_fall_for_tail ---
s/\bn369_out\b/formation_fwd_fall_for_tail_out/g
s/\bn369\b/formation_fwd_fall_for_tail/g

# --- n368 express_umi_set_and ---
s/\bn368_out\b/express_umi_set_and_out/g
s/\bn368\b/express_umi_set_and/g

# --- n367 tail_sign_set_or ---
s/\bn367_out\b/tail_sign_set_or_out/g
s/\bn367\b/tail_sign_set_or/g

# --- n366 tail_sign_reset_or ---
s/\bn366_out\b/tail_sign_reset_or_out/g
s/\bn366\b/tail_sign_reset_or/g

# --- n365 tail_sign_latch_unused (SR_LATCH, no outputs referenced) ---
s/\bn365\b/tail_sign_latch_unused/g

# --- n364 drive_front_sign_read ---
s/\bn364_out\b/drive_front_sign_read_out/g
s/\bn364\b/drive_front_sign_read/g

# --- n363 front_drive_rise_pulse ---
s/\bn363_out\b/front_drive_rise_pulse_out/g
s/\bn363\b/front_drive_rise_pulse/g

# --- n362 front_drive_fall_pulse ---
s/\bn362_out\b/front_drive_fall_pulse_out/g
s/\bn362\b/front_drive_fall_pulse/g

# --- n361 formation_fwd_fall_for_front ---
s/\bn361_out\b/formation_fwd_fall_for_front_out/g
s/\bn361\b/formation_fwd_fall_for_front/g

# --- n360 front_sign_set_and ---
s/\bn360_out\b/front_sign_set_and_out/g
s/\bn360\b/front_sign_set_and/g

# --- n359 front_sign_set_or ---
s/\bn359_out\b/front_sign_set_or_out/g
s/\bn359\b/front_sign_set_or/g

# --- n357 front_sign_reset_or ---
s/\bn357_out\b/front_sign_reset_or_out/g
s/\bn357\b/front_sign_reset_or/g

# --- n356 front_sign_latch (SR_LATCH, q outputs to port) ---
s/\bn356\b/front_sign_latch/g

# --- n332 const_notch_max ---
s/\bn332_value\b/const_notch_max_value/g
s/\bn332\b/const_notch_max/g

# --- n328 atc_limit2_read ---
s/\bn328_out\b/atc_limit2_read_out/g
s/\bn328\b/atc_limit2_read/g

# --- n327 atc_limit1_read ---
s/\bn327_out\b/atc_limit1_read_out/g
s/\bn327\b/atc_limit1_read/g

# --- n326 atc_eb_read ---
s/\bn326_out\b/atc_eb_read_out/g
s/\bn326\b/atc_eb_read/g

# --- n325 const_atc_limit2_notch ---
s/\bn325_value\b/const_atc_limit2_notch_value/g
s/\bn325\b/const_atc_limit2_notch/g

# --- n324 const_atc_limit1_notch ---
s/\bn324_value\b/const_atc_limit1_notch_value/g
s/\bn324\b/const_atc_limit1_notch/g

# --- n323 const_atc_eb_notch ---
s/\bn323_value\b/const_atc_eb_notch_value/g
s/\bn323\b/const_atc_eb_notch/g

# --- n322 atc_limit2_sw ---
s/\bn322_out\b/atc_limit2_sw_out/g
s/\bn322\b/atc_limit2_sw/g

# --- n321 atc_limit1_sw ---
s/\bn321_out\b/atc_limit1_sw_out/g
s/\bn321\b/atc_limit1_sw/g

# --- n320 effective_limit ---
s/\bn320_out\b/effective_limit_out/g
s/\bn320\b/effective_limit/g

# --- n319 atc_eb_limit_sw ---
s/\bn319_out\b/atc_eb_limit_sw_out/g
s/\bn319\b/atc_eb_limit_sw/g

# --- n316 buzzer_no_simif_func ---
s/\bn316_out\b/buzzer_no_simif_func_out/g
s/\bn316\b/buzzer_no_simif_func/g

# --- n301 crew_drive_ch9_read ---
s/\bn301_out\b/crew_drive_ch9_read_out/g
s/\bn301\b/crew_drive_ch9_read/g

# --- n300 crew_left_door_rel ---
s/\bn300_out\b/crew_left_door_rel_out/g
s/\bn300\b/crew_left_door_rel/g

# --- n299 crew_left_ch2_read ---
s/\bn299_out\b/crew_left_ch2_read_out/g
s/\bn299\b/crew_left_ch2_read/g

# --- n298 settings_ch26_read ---
s/\bn298_out\b/settings_ch26_read_out/g
s/\bn298\b/settings_ch26_read/g

# --- n297 crew_drive_ch8_read ---
s/\bn297_out\b/crew_drive_ch8_read_out/g
s/\bn297\b/crew_drive_ch8_read/g

# --- n296 crew_left_door_ok ---
s/\bn296_out\b/crew_left_door_ok_out/g
s/\bn296\b/crew_left_door_ok/g

# --- n295 crew_left_ch1_read ---
s/\bn295_out\b/crew_left_ch1_read_out/g
s/\bn295\b/crew_left_ch1_read/g

# --- n294 settings_ch25_read ---
s/\bn294_out\b/settings_ch25_read_out/g
s/\bn294\b/settings_ch25_read/g

# --- n293 crew_drive_ch7_read ---
s/\bn293_out\b/crew_drive_ch7_read_out/g
s/\bn293\b/crew_drive_ch7_read/g

# --- n292 crew_right_door_rel ---
s/\bn292_out\b/crew_right_door_rel_out/g
s/\bn292\b/crew_right_door_rel/g

# --- n291 crew_right_ch2_read ---
s/\bn291_out\b/crew_right_ch2_read_out/g
s/\bn291\b/crew_right_ch2_read/g

# --- n290 settings_ch21_read ---
s/\bn290_out\b/settings_ch21_read_out/g
s/\bn290\b/settings_ch21_read/g

# --- n289 crew_drive_ch6_read ---
s/\bn289_out\b/crew_drive_ch6_read_out/g
s/\bn289\b/crew_drive_ch6_read/g

# --- n288 crew_right_door_ok ---
s/\bn288_out\b/crew_right_door_ok_out/g
s/\bn288\b/crew_right_door_ok/g

# --- n286 crew_right_ch1_read ---
s/\bn286_out\b/crew_right_ch1_read_out/g
s/\bn286\b/crew_right_ch1_read/g

# --- n285 settings_ch20_read ---
s/\bn285_out\b/settings_ch20_read_out/g
s/\bn285\b/settings_ch20_read/g

# --- n284 settings_ch5_read ---
s/\bn284_out\b/settings_ch5_read_out/g
s/\bn284\b/settings_ch5_read/g

# --- n283 crew_interlock_sw ---
s/\bn283_out\b/crew_interlock_sw_out/g
s/\bn283\b/crew_interlock_sw/g

# --- n282 crew_drive_ch10_read ---
s/\bn282_out\b/crew_drive_ch10_read_out/g
s/\bn282\b/crew_drive_ch10_read/g

# --- n281 crew_left_ch3_read ---
s/\bn281_out\b/crew_left_ch3_read_out/g
s/\bn281\b/crew_left_ch3_read/g

# --- n280 crew_right_ch3_read ---
s/\bn280_out\b/crew_right_ch3_read_out/g
s/\bn280\b/crew_right_ch3_read/g

# --- n279 settings_ch28_read ---
s/\bn279_out\b/settings_ch28_read_out/g
s/\bn279\b/settings_ch28_read/g

# --- n278 settings_ch23_read ---
s/\bn278_out\b/settings_ch23_read_out/g
s/\bn278\b/settings_ch23_read/g

# --- n277 crew_warning_func ---
s/\bn277_out\b/crew_warning_func_out/g
s/\bn277\b/crew_warning_func/g

# --- n276 crew_left_ch4_read ---
s/\bn276_out\b/crew_left_ch4_read_out/g
s/\bn276\b/crew_left_ch4_read/g

# --- n275 crew_right_ch4_read ---
s/\bn275_out\b/crew_right_ch4_read_out/g
s/\bn275\b/crew_right_ch4_read/g

# --- n264 formation_lever_func (outputs to port) ---
s/\bn264\b/formation_lever_func/g

# --- n260 settings_ch14_read ---
s/\bn260_out\b/settings_ch14_read_out/g
s/\bn260\b/settings_ch14_read/g

# --- n259 settings_ch13_read ---
s/\bn259_out\b/settings_ch13_read_out/g
s/\bn259\b/settings_ch13_read/g

# --- n258 mascon_key_not ---
s/\bn258_out\b/mascon_key_not_out/g
s/\bn258\b/mascon_key_not/g

# --- n257 formation_fwd_thresh ---
s/\bn257_out\b/formation_fwd_thresh_out/g
s/\bn257\b/formation_fwd_thresh/g

# --- n256 formation_counter ---
s/\bn256_out\b/formation_counter_out/g
s/\bn256\b/formation_counter/g

# --- n255 formation_dn_pulse ---
s/\bn255_out\b/formation_dn_pulse_out/g
s/\bn255\b/formation_dn_pulse/g

# --- n254 formation_up_pulse ---
s/\bn254_out\b/formation_up_pulse_out/g
s/\bn254\b/formation_up_pulse/g

# --- n230 settings_ch8_read ---
s/\bn230_out\b/settings_ch8_read_out/g
s/\bn230\b/settings_ch8_read/g

# --- n217 settings_ch7_read ---
s/\bn217_out\b/settings_ch7_read_out/g
s/\bn217\b/settings_ch7_read/g

# --- Two-digit IDs ---

# --- n168 seat_emergency_read ---
s/\bn168_out\b/seat_emergency_read_out/g
s/\bn168\b/seat_emergency_read/g

# --- n167 handle_reset_or ---
s/\bn167_out\b/handle_reset_or_out/g
s/\bn167\b/handle_reset_or/g

# --- n166 forward_fast_up ---
s/\bn166_out\b/forward_fast_up_out/g
s/\bn166\b/forward_fast_up/g

# --- n165 forward_up_blinker ---
s/\bn165_out\b/forward_up_blinker_out/g
s/\bn165\b/forward_up_blinker/g

# --- n164 forward_up_cap ---
s/\bn164_out\b/forward_up_cap_out/g
s/\bn164\b/forward_up_cap/g

# --- n163 forward_up_pulse_both ---
s/\bn163_out\b/forward_up_pulse_both_out/g
s/\bn163\b/forward_up_pulse_both/g

# --- n158 handle_fast_up ---
s/\bn158_out\b/handle_fast_up_out/g
s/\bn158\b/handle_fast_up/g

# --- n157 handle_up_blinker ---
s/\bn157_out\b/handle_up_blinker_out/g
s/\bn157\b/handle_up_blinker/g

# --- n156 handle_up_cap ---
s/\bn156_out\b/handle_up_cap_out/g
s/\bn156\b/handle_up_cap/g

# --- n155 handle_up_pulse_both ---
s/\bn155_out\b/handle_up_pulse_both_out/g
s/\bn155\b/handle_up_pulse_both/g

# --- n154 handle_fast_dn ---
s/\bn154_out\b/handle_fast_dn_out/g
s/\bn154\b/handle_fast_dn/g

# --- n152 drive_ch2_read ---
s/\bn152_out\b/drive_ch2_read_out/g
s/\bn152\b/drive_ch2_read/g

# --- n151 settings_ch2_read ---
s/\bn151_out\b/settings_ch2_read_out/g
s/\bn151\b/settings_ch2_read/g

# --- n150 crew_buzzer_pulse ---
s/\bn150_out\b/crew_buzzer_pulse_out/g
s/\bn150\b/crew_buzzer_pulse/g

# --- n148 drive_ch12_read ---
s/\bn148_out\b/drive_ch12_read_out/g
s/\bn148\b/drive_ch12_read/g

# --- n147 settings_ch29_read ---
s/\bn147_out\b/settings_ch29_read_out/g
s/\bn147\b/settings_ch29_read/g

# --- n146 settings_ch24_read ---
s/\bn146_out\b/settings_ch24_read_out/g
s/\bn146\b/settings_ch24_read/g

# --- n145 seat_buzzer_read ---
s/\bn145_out\b/seat_buzzer_read_out/g
s/\bn145\b/seat_buzzer_read/g

# --- n144 crew_buzzer_func (both internal _out and port output) ---
s/\bn144_out\b/crew_buzzer_func_out/g
s/\bn144\b/crew_buzzer_func/g

# --- n139 simif_rx_ch2_bool_read ---
s/\bn139_out\b/simif_rx_ch2_bool_read_out/g
s/\bn139\b/simif_rx_ch2_bool_read/g

# --- n119 reverser_sound_thresh (outputs to port) ---
s/\bn119\b/reverser_sound_thresh/g

# --- n118 reverser_delta ---
s/\bn118_out\b/reverser_delta_out/g
s/\bn118\b/reverser_delta/g

# --- n110 reverser_counter (both internal _out and port output) ---
s/\bn110_out\b/reverser_counter_out/g
s/\bn110\b/reverser_counter/g

# --- n106 reverser_dn_pulse ---
s/\bn106_out\b/reverser_dn_pulse_out/g
s/\bn106\b/reverser_dn_pulse/g

# --- n105 reverser_up_pulse ---
s/\bn105_out\b/reverser_up_pulse_out/g
s/\bn105\b/reverser_up_pulse/g

# --- n104 reverser_dn_thresh ---
s/\bn104_out\b/reverser_dn_thresh_out/g
s/\bn104\b/reverser_dn_thresh/g

# --- n103 reverser_up_thresh ---
s/\bn103_out\b/reverser_up_thresh_out/g
s/\bn103\b/reverser_up_thresh/g

# --- n102 seat_reverser_num_read ---
s/\bn102_out\b/seat_reverser_num_read_out/g
s/\bn102\b/seat_reverser_num_read/g

# --- n80 brake_force_func ---
s/\bn80_out\b/brake_force_func_out/g
s/\bn80\b/brake_force_func/g

# --- n79 power_limit_func ---
s/\bn79_out\b/power_limit_func_out/g
s/\bn79\b/power_limit_func/g

# --- n65 handle_angle_func ---
s/\bn65_out\b/handle_angle_func_out/g
s/\bn65\b/handle_angle_func/g

# --- n58 handle_sound_thresh ---
s/\bn58_out\b/handle_sound_thresh_out/g
s/\bn58\b/handle_sound_thresh/g

# --- n57 handle_notch_delta ---
s/\bn57_out\b/handle_notch_delta_out/g
s/\bn57\b/handle_notch_delta/g

# --- n55 handle_sound_toggle (outputs to port) ---
s/\bn55\b/handle_sound_toggle/g

# --- n49 const_notch_disengaged ---
s/\bn49_value\b/const_notch_disengaged_value/g
s/\bn49\b/const_notch_disengaged/g

# --- n48 handle_notch_sw ---
s/\bn48_out\b/handle_notch_sw_out/g
s/\bn48\b/handle_notch_sw/g

# --- n45 notch_positive ---
s/\bn45_out\b/notch_positive_out/g
s/\bn45\b/notch_positive/g

# --- n44 fwd_fast_while_pos ---
s/\bn44_out\b/fwd_fast_while_pos_out/g
s/\bn44\b/fwd_fast_while_pos/g

# --- n43 fwd_fast_while_neg ---
s/\bn43_out\b/fwd_fast_while_neg_out/g
s/\bn43\b/fwd_fast_while_neg/g

# --- n41 notch_negative ---
s/\bn41_out\b/notch_negative_out/g
s/\bn41\b/notch_negative/g

# --- n37 seat_forward_rise_pulse ---
s/\bn37_out\b/seat_forward_rise_pulse_out/g
s/\bn37\b/seat_forward_rise_pulse/g

# --- n36 seat_forward_up_thresh ---
s/\bn36_out\b/seat_forward_up_thresh_out/g
s/\bn36\b/seat_forward_up_thresh/g

# --- n35 notch_up_func ---
s/\bn35_out\b/notch_up_func_out/g
s/\bn35\b/notch_up_func/g

# --- n34 latch_set_func ---
s/\bn34_out\b/latch_set_func_out/g
s/\bn34\b/latch_set_func/g

# --- n32 seat_engaged_bool_read ---
s/\bn32_out\b/seat_engaged_bool_read_out/g
s/\bn32\b/seat_engaged_bool_read/g

# --- n31 handle_engaged_and ---
s/\bn31_out\b/handle_engaged_and_out/g
s/\bn31\b/handle_engaged_and/g

# --- n30 latch_reset_func ---
s/\bn30_out\b/latch_reset_func_out/g
s/\bn30\b/latch_reset_func/g

# --- n23 seat_forward_dn_thresh ---
s/\bn23_out\b/seat_forward_dn_thresh_out/g
s/\bn23\b/seat_forward_dn_thresh/g

# --- n22 seat_forward_num_read ---
s/\bn22_out\b/seat_forward_num_read_out/g
s/\bn22\b/seat_forward_num_read/g

# --- n21 notch_dn_func ---
s/\bn21_out\b/notch_dn_func_out/g
s/\bn21\b/notch_dn_func/g

# --- n20 seat_latch (SR_LATCH with _q and _not_q) ---
s/\bn20_not_q\b/seat_latch_not_q/g
s/\bn20_q\b/seat_latch_q/g
s/\bn20\b/seat_latch/g

# --- n18 handle_dn_blinker ---
s/\bn18_out\b/handle_dn_blinker_out/g
s/\bn18\b/handle_dn_blinker/g

# --- n17 handle_dn_cap ---
s/\bn17_out\b/handle_dn_cap_out/g
s/\bn17\b/handle_dn_cap/g

# --- n16 handle_dn_pulse_both ---
s/\bn16_out\b/handle_dn_pulse_both_out/g
s/\bn16\b/handle_dn_pulse_both/g

# --- n12 handle_dn_pulse ---
s/\bn12_out\b/handle_dn_pulse_out/g
s/\bn12\b/handle_dn_pulse/g

# --- n11 handle_up_pulse ---
s/\bn11_out\b/handle_up_pulse_out/g
s/\bn11\b/handle_up_pulse/g

# --- Single-digit IDs last ---

# --- n9 handle_notch ---
s/\bn9_out\b/handle_notch_out/g
s/\bn9\b/handle_notch/g

# --- n8 handle_pos_dn_thresh ---
s/\bn8_out\b/handle_pos_dn_thresh_out/g
s/\bn8\b/handle_pos_dn_thresh/g

# --- n7 handle_pos_up_thresh ---
s/\bn7_out\b/handle_pos_up_thresh_out/g
s/\bn7\b/handle_pos_up_thresh/g

# --- n6 seat_handle_num_read ---
s/\bn6_out\b/seat_handle_num_read_out/g
s/\bn6\b/seat_handle_num_read/g
