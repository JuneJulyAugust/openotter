# Brushless Motor & ESC Specifications

## 3650 3900KV Brushless Motor
- **KV Rating:** 3900 RPM/V
- **Max RPM:** 50,000
- **Max Voltage:** <13V
- **Max Current:** 69A
- **Wattage:** 900W
- **Dimensions:** 36mm dia x 50mm length
- **Shaft:** 3.175mm outer, 5.00mm inner, 15mm length
- **Connector:** 4mm banana plug
- **Bearings:** Dual ball bearing

## 45A Brushless ESC
- **Continuous / Burst Current:** 45A / 180A
- **Battery:** 2-3S LiPo (7.4-11.1V) or 4-9S NiMH/NiCd
- **BEC Output:** 5.8V / 3A
- **Power Connector:** T-plug (Deans) male
- **Signal:** Standard servo PWM (50Hz, 1000-2000us)

### ESC Programmable Settings (via card)
| Setting | Options |
|---|---|
| Low Voltage Cutoff | 3.1V/cell, 2.8V/cell, 3.3V/cell, disabled |
| Start Mode | Medium, Soft, Strong |
| Max Brake Force | 25%, 50%, 75%, 100% |
| Max Reverse Force | 25%, 50%, 75%, 100% |
| Neutral Range | 6%, 9%, 12% |

## Control Protocol
ESC accepts standard servo PWM via Arduino `Servo` library:
- **1000us (Servo.write(0)):** Full brake / minimum
- **1500us (Servo.write(90)):** Neutral / idle
- **2000us (Servo.write(180)):** Full throttle

### Power-On & Arming Sequence
1. **Connect LiPo battery to ESC** via T-plug — the ESC will not power up from USB alone
2. Connect Arduino to host via USB (for programming and serial monitor)
3. Upload sketch — ESC signal starts at neutral (1500us / write(90))
4. ESC emits confirmation beeps (~2-3 seconds)
5. Motor is now armed and responds to throttle commands

### Safety
- **Always** connect battery before uploading the motor sketch
- **Always** arm at neutral before sending throttle
- **Never** start with throttle above neutral — ESC will refuse to arm
- Motor draws extreme current at high throttle; ensure battery can deliver
- Keep propellers/loads detached during initial testing
