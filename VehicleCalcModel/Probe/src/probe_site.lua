-- Site knowledge: coordinates on the x axis [m] just before the vehicle can no
-- longer continue (user-measured, no margin added). probe_core never leaves
-- IDLE while either is nil.
SITE_LO = -8480
SITE_HI = 480
-- Sign of the x change per +motor (verified by measurement: +motor increases x).
-- Lets the jog work again after the script is reloaded; probe_dir overrides it.
SITE_DIR = 1
