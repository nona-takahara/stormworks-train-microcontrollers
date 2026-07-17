# --- Two-digit IDs first (prevent partial match with n8, n9) ---

# --- n60 door_cmd_gate ---
s/\bn60_out\b/door_cmd_gate_out/g
s/\bn60\b/door_cmd_gate/g

# --- n59 nits_ext_enable_read ---
s/\bn59_out\b/nits_ext_enable_read_out/g
s/\bn59\b/nits_ext_enable_read/g

# --- n58 haptic_decay_cap ---
s/\bn58_out\b/haptic_decay_cap_out/g
s/\bn58\b/haptic_decay_cap/g

# --- n57 haptic_slow_strength ---
s/\bn57_value\b/haptic_slow_strength_value/g
s/\bn57\b/haptic_slow_strength/g

# --- n56 haptic_fast_strength ---
s/\bn56_value\b/haptic_fast_strength_value/g
s/\bn56\b/haptic_fast_strength/g

# --- n55 haptic_strength_sw ---
s/\bn55_out\b/haptic_strength_sw_out/g
s/\bn55\b/haptic_strength_sw/g

# --- n54 haptic_output_mul (outputs to port) ---
s/\bn54\b/haptic_output_mul/g

# --- n53 const_close_dir ---
s/\bn53_value\b/const_close_dir_value/g
s/\bn53\b/const_close_dir/g

# --- n52 const_open_dir ---
s/\bn52_value\b/const_open_dir_value/g
s/\bn52\b/const_open_dir/g

# --- n51 door_dir_sw ---
s/\bn51_out\b/door_dir_sw_out/g
s/\bn51\b/door_dir_sw/g

# --- n50 chime_low_phase2 ---
s/\bn50_out\b/chime_low_phase2_out/g
s/\bn50\b/chime_low_phase2/g

# --- n49 chime_high_phase2 ---
s/\bn49_out\b/chime_high_phase2_out/g
s/\bn49\b/chime_high_phase2/g

# --- n48 chime_low_phase1 ---
s/\bn48_out\b/chime_low_phase1_out/g
s/\bn48\b/chime_low_phase1/g

# --- n47 chime_high_phase1 ---
s/\bn47_out\b/chime_high_phase1_out/g
s/\bn47\b/chime_high_phase1/g

# --- n46 chime_low_or (outputs to port) ---
s/\bn46\b/chime_low_or/g

# --- n45 chime_high_or (outputs to port) ---
s/\bn45\b/chime_high_or/g

# --- n44 chime_timer ---
s/\bn44_out\b/chime_timer_out/g
s/\bn44\b/chime_timer/g

# --- n43 chime_counter_disable ---
s/\bn43_out\b/chime_counter_disable_out/g
s/\bn43\b/chime_counter_disable/g

# --- n42 door_state_edge ---
s/\bn42_out\b/door_state_edge_out/g
s/\bn42\b/door_state_edge/g

# --- n41 door_close_trigger ---
s/\bn41_out\b/door_close_trigger_out/g
s/\bn41\b/door_close_trigger/g

# --- n40 door_open_latch ---
s/\bn40_q\b/door_open_latch_q/g
s/\bn40\b/door_open_latch/g

# --- n39 door_close_cmd_read ---
s/\bn39_out\b/door_close_cmd_read_out/g
s/\bn39\b/door_close_cmd_read/g

# --- n38 door_paired_ch ---
s/\bn38_out\b/door_paired_ch_out/g
s/\bn38\b/door_paired_ch/g

# --- n36 door_side_ch ---
s/\bn36_out\b/door_side_ch_out/g
s/\bn36\b/door_side_ch/g

# --- n35 door_cmd_read ---
s/\bn35_out\b/door_cmd_read_out/g
s/\bn35\b/door_cmd_read/g

# --- n23 closed_dist_max_sq ---
s/\bn23_out\b/closed_dist_max_sq_out/g
s/\bn23\b/closed_dist_max_sq/g

# --- n22 closed_dist_min_sq ---
s/\bn22_out\b/closed_dist_min_sq_out/g
s/\bn22\b/closed_dist_min_sq/g

# --- n21 door_detect_width ---
s/\bn21_out\b/door_detect_width_out/g
s/\bn21\b/door_detect_width/g

# --- n20 door_detect_length ---
s/\bn20_out\b/door_detect_length_out/g
s/\bn20\b/door_detect_length/g

# --- n19 phys_door_open ---
s/\bn19_out\b/phys_door_open_out/g
s/\bn19\b/phys_door_open/g

# --- n18 dist_below_closed_max ---
s/\bn18_out\b/dist_below_closed_max_out/g
s/\bn18\b/dist_below_closed_max/g

# --- n17 dist_above_closed_min ---
s/\bn17_out\b/dist_above_closed_min_out/g
s/\bn17\b/dist_above_closed_min/g

# --- n16 sensor_dist_sq ---
s/\bn16_out\b/sensor_dist_sq_out/g
s/\bn16\b/sensor_dist_sq/g

# --- n14 phys_b_pos_z ---
s/\bn14_out\b/phys_b_pos_z_out/g
s/\bn14\b/phys_b_pos_z/g

# --- n13 phys_b_pos_y ---
s/\bn13_out\b/phys_b_pos_y_out/g
s/\bn13\b/phys_b_pos_y/g

# --- n12 phys_b_pos_x ---
s/\bn12_out\b/phys_b_pos_x_out/g
s/\bn12\b/phys_b_pos_x/g

# --- n11 phys_a_pos_z ---
s/\bn11_out\b/phys_a_pos_z_out/g
s/\bn11\b/phys_a_pos_z/g

# --- n10 phys_a_pos_y ---
s/\bn10_out\b/phys_a_pos_y_out/g
s/\bn10\b/phys_a_pos_y/g

# --- Single-digit IDs last ---

# --- n9 phys_a_pos_x ---
s/\bn9_out\b/phys_a_pos_x_out/g
s/\bn9\b/phys_a_pos_x/g

# --- n8 door_open_or (outputs to port) ---
s/\bn8\b/door_open_or/g
