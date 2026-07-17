# ============================================================
# Three-digit node IDs first
# ============================================================

# --- n620 atc_train_length (outputs to port) ---
s/\bn620\b/atc_train_length/g

# --- n619 atc_car_count_high_read ---
s/\bn619_out\b/atc_car_count_high_read_out/g
s/\bn619\b/atc_car_count_high_read/g

# --- n618 atc_car_count_low_read ---
s/\bn618_out\b/atc_car_count_low_read_out/g
s/\bn618\b/atc_car_count_low_read/g

# --- n614 high_beam_y ---
s/\bn614_out\b/high_beam_y_out/g
s/\bn614\b/high_beam_y/g

# --- n613 low_beam_y ---
s/\bn613_out\b/low_beam_y_out/g
s/\bn613\b/low_beam_y/g

# --- n612 high_beam_x ---
s/\bn612_out\b/high_beam_x_out/g
s/\bn612\b/high_beam_x/g

# --- n611 low_beam_x ---
s/\bn611_out\b/low_beam_x_out/g
s/\bn611\b/low_beam_x/g

# --- n609 headlight_beam_x_sw ---
s/\bn609_out\b/headlight_beam_x_sw_out/g
s/\bn609\b/headlight_beam_x_sw/g

# --- n608 display_val_2_read ---
s/\bn608_out\b/display_val_2_read_out/g
s/\bn608\b/display_val_2_read/g

# --- n607 display_val_1_read ---
s/\bn607_out\b/display_val_1_read_out/g
s/\bn607\b/display_val_1_read/g

# --- n606 display_vals_composite ---
s/\bn606_out\b/display_vals_composite_out/g
s/\bn606\b/display_vals_composite/g

# --- n605 rolling_composite_ch8_read ---
s/\bn605_out\b/rolling_composite_ch8_read_out/g
s/\bn605\b/rolling_composite_ch8_read/g

# --- n604 electricity_bool_header ---
s/\bn604_out\b/electricity_bool_header_out/g
s/\bn604\b/electricity_bool_header/g

# --- n601 display_mode_flag_read ---
s/\bn601_out\b/display_mode_flag_read_out/g
s/\bn601\b/display_mode_flag_read/g

# --- n600 display_mode_bool_composite ---
s/\bn600_out\b/display_mode_bool_composite_out/g
s/\bn600\b/display_mode_bool_composite/g

# --- n599 const_atp_mode_2 ---
s/\bn599_value\b/const_atp_mode_2_value/g
s/\bn599\b/const_atp_mode_2/g

# --- n598 const_atp_mode_active ---
s/\bn598_value\b/const_atp_mode_active_value/g
s/\bn598\b/const_atp_mode_active/g

# --- n597 atp_mode_toggle ---
s/\bn597_out\b/atp_mode_toggle_out/g
s/\bn597\b/atp_mode_toggle/g

# --- n594 display_flag_7_read ---
s/\bn594_out\b/display_flag_7_read_out/g
s/\bn594\b/display_flag_7_read/g

# --- n593 display_flag_8_read ---
s/\bn593_out\b/display_flag_8_read_out/g
s/\bn593\b/display_flag_8_read/g

# --- n590 signal_flag_read ---
s/\bn590_out\b/signal_flag_read_out/g
s/\bn590\b/signal_flag_read/g

# --- n589 regen_current_rolling_read ---
s/\bn589_out\b/regen_current_rolling_read_out/g
s/\bn589\b/regen_current_rolling_read/g

# --- n588 motor_current_rolling_read ---
s/\bn588_out\b/motor_current_rolling_read_out/g
s/\bn588\b/motor_current_rolling_read/g

# --- n586 regen_current_delta ---
s/\bn586_out\b/regen_current_delta_out/g
s/\bn586\b/regen_current_delta/g

# --- n585 regen_current_smooth ---
s/\bn585_out\b/regen_current_smooth_out/g
s/\bn585\b/regen_current_smooth/g

# --- n583 smooth_alpha ---
s/\bn583_value\b/smooth_alpha_value/g
s/\bn583\b/smooth_alpha/g

# --- n582 motor_current_delta ---
s/\bn582_out\b/motor_current_delta_out/g
s/\bn582\b/motor_current_delta/g

# --- n581 motor_current_smooth ---
s/\bn581_out\b/motor_current_smooth_out/g
s/\bn581\b/motor_current_smooth/g

# --- n580 const_euler ---
s/\bn580_value\b/const_euler_value/g
s/\bn580\b/const_euler/g

# --- n579 regen_current_raw_read ---
s/\bn579_out\b/regen_current_raw_read_out/g
s/\bn579\b/regen_current_raw_read/g

# --- n578 motor_current_raw_read ---
s/\bn578_out\b/motor_current_raw_read_out/g
s/\bn578\b/motor_current_raw_read/g

# --- n577 electricity_display_composite ---
s/\bn577_out\b/electricity_display_composite_out/g
s/\bn577\b/electricity_display_composite/g

# --- n576 electricity_panel_lua (outputs to port) ---
s/\bn576\b/electricity_panel_lua/g

# --- n573 atc_mode_active_read ---
s/\bn573_out\b/atc_mode_active_read_out/g
s/\bn573\b/atc_mode_active_read/g

# --- n572 arc_speed_clamped ---
s/\bn572_out\b/arc_speed_clamped_out/g
s/\bn572\b/arc_speed_clamped/g

# --- n570 atsc_setting_3_read ---
s/\bn570_out\b/atsc_setting_3_read_out/g
s/\bn570\b/atsc_setting_3_read/g

# --- n569 atsc_setting_2_read ---
s/\bn569_out\b/atsc_setting_2_read_out/g
s/\bn569\b/atsc_setting_2_read/g

# --- n568 atsc_setting_1_read ---
s/\bn568_out\b/atsc_setting_1_read_out/g
s/\bn568\b/atsc_setting_1_read/g

# --- n567 atp_switch_active_read ---
s/\bn567_out\b/atp_switch_active_read_out/g
s/\bn567\b/atp_switch_active_read/g

# --- n553 monitor_flag_11_read ---
s/\bn553_out\b/monitor_flag_11_read_out/g
s/\bn553\b/monitor_flag_11_read/g

# --- n552 display_bool_composite ---
s/\bn552_out\b/display_bool_composite_out/g
s/\bn552\b/display_bool_composite/g

# --- n551 display_num_composite ---
s/\bn551_out\b/display_num_composite_out/g
s/\bn551\b/display_num_composite/g

# --- n538 bc_pressure_read ---
s/\bn538_out\b/bc_pressure_read_out/g
s/\bn538\b/bc_pressure_read/g

# --- n527 atp_mode_gate_enable_read ---
s/\bn527_out\b/atp_mode_gate_enable_read_out/g
s/\bn527\b/atp_mode_gate_enable_read/g

# --- n526 atp_mode_gate_sw ---
s/\bn526_out\b/atp_mode_gate_sw_out/g
s/\bn526\b/atp_mode_gate_sw/g

# --- n524 arc_major_count_read ---
s/\bn524_out\b/arc_major_count_read_out/g
s/\bn524\b/arc_major_count_read/g

# --- n523 arc_minor_count_read ---
s/\bn523_out\b/arc_minor_count_read_out/g
s/\bn523\b/arc_minor_count_read/g

# --- n517 arc_calc (outputs to ARC port) ---
s/\bn517\b/arc_calc/g

# --- n511 atc_flag_2_read ---
s/\bn511_out\b/atc_flag_2_read_out/g
s/\bn511\b/atc_flag_2_read/g

# --- n510 atc_flag_1_read ---
s/\bn510_out\b/atc_flag_1_read_out/g
s/\bn510\b/atc_flag_1_read/g

# --- n499 monitor_flag_15_read ---
s/\bn499_out\b/monitor_flag_15_read_out/g
s/\bn499\b/monitor_flag_15_read/g

# --- n498 monitor_flag_14_read ---
s/\bn498_out\b/monitor_flag_14_read_out/g
s/\bn498\b/monitor_flag_14_read/g

# --- n497 atsc_bool_write ---
s/\bn497_out\b/atsc_bool_write_out/g
s/\bn497\b/atsc_bool_write/g

# --- n419 display_compositor_lua ---
s/\bn419_video\b/display_compositor_lua_video/g
s/\bn419\b/display_compositor_lua/g

# --- n417 display_init_lua ---
s/\bn417\b/display_init_lua/g

# --- n415 main_monitor_lua (outputs to port) ---
s/\bn415\b/main_monitor_lua/g

# --- n411 atp_active_sw ---
s/\bn411_out\b/atp_active_sw_out/g
s/\bn411\b/atp_active_sw/g

# --- n407 atc_setting_3_sw ---
s/\bn407_out\b/atc_setting_3_sw_out/g
s/\bn407\b/atc_setting_3_sw/g

# --- n391 atp_mode_composite_write ---
s/\bn391_out\b/atp_mode_composite_write_out/g
s/\bn391\b/atp_mode_composite_write/g

# --- n390 atp_switch_panel_lua (outputs to port) ---
s/\bn390\b/atp_switch_panel_lua/g

# --- n389 const_atp_mode_1 ---
s/\bn389_value\b/const_atp_mode_1_value/g
s/\bn389\b/const_atp_mode_1/g

# --- n388 atp_toggle_trigger ---
s/\bn388_out\b/atp_toggle_trigger_out/g
s/\bn388\b/atp_toggle_trigger/g

# --- n387 atp_touch_fall_pulse ---
s/\bn387_out\b/atp_touch_fall_pulse_out/g
s/\bn387\b/atp_touch_fall_pulse/g

# --- n386 atp_touch_read ---
s/\bn386_out\b/atp_touch_read_out/g
s/\bn386\b/atp_touch_read/g

# --- n385 atp_mode_sw ---
s/\bn385_out\b/atp_mode_sw_out/g
s/\bn385\b/atp_mode_sw/g

# --- n349 atc_panel_lua ---
s/\bn349_video\b/atc_panel_lua_video/g
s/\bn349\b/atc_panel_lua/g

# --- n347 display_template_lua ---
s/\bn347_video\b/display_template_lua_video/g
s/\bn347\b/display_template_lua/g

# --- n334 ats_panel_lua ---
s/\bn334_video\b/ats_panel_lua_video/g
s/\bn334\b/ats_panel_lua/g

# ============================================================
# Two-digit node IDs
# ============================================================

# --- n81 composite_data_display_lua ---
s/\bn81_video\b/composite_data_display_lua_video/g
s/\bn81\b/composite_data_display_lua/g

# --- n131 headlight_beam_y_sw ---
s/\bn131_out\b/headlight_beam_y_sw_out/g
s/\bn131\b/headlight_beam_y_sw/g

# --- n132 headlight_high_beam_read ---
s/\bn132_out\b/headlight_high_beam_read_out/g
s/\bn132\b/headlight_high_beam_read/g

# --- n129 loop_start_atsc_write (outputs to port) ---
s/\bn129\b/loop_start_atsc_write/g

# ============================================================
# Single-digit node IDs last
# ============================================================

# --- n4 main_display_filter_lua ---
s/\bn4_video\b/main_display_filter_lua_video/g
s/\bn4\b/main_display_filter_lua/g

# ============================================================
# Fix script_ref paths (reverse the rename for .lua file paths)
# ============================================================
s#script_ref="scripts/main_display_filter_lua\.lua"#script_ref="scripts/n4.lua"#
s#script_ref="scripts/composite_data_display_lua\.lua"#script_ref="scripts/n81.lua"#
s#script_ref="scripts/ats_panel_lua\.lua"#script_ref="scripts/n334.lua"#
s#script_ref="scripts/display_template_lua\.lua"#script_ref="scripts/n347.lua"#
s#script_ref="scripts/atc_panel_lua\.lua"#script_ref="scripts/n349.lua"#
s#script_ref="scripts/atp_switch_panel_lua\.lua"#script_ref="scripts/n390.lua"#
s#script_ref="scripts/main_monitor_lua\.lua"#script_ref="scripts/n415.lua"#
s#script_ref="scripts/display_init_lua\.lua"#script_ref="scripts/n417.lua"#
s#script_ref="scripts/display_compositor_lua\.lua"#script_ref="scripts/n419.lua"#
s#script_ref="scripts/electricity_panel_lua\.lua"#script_ref="scripts/n576.lua"#
