# FPGA Bidirectional Morse Code Transceiver

![VHDL](https://img.shields.io/badge/VHDL-IEEE_1076-blue)
![FPGA](https://img.shields.io/badge/FPGA-Basys_3-success)
![Tool](https://img.shields.io/badge/Xilinx-Vivado-red)
![License](https://img.shields.io/badge/License-MIT-green)

A bidirectional Morse code transceiver implemented in **VHDL** on the **Digilent Basys 3 (Artix-7 FPGA)**. The system supports both **manual Morse decoding** and **automatic Morse encoding**, combining finite state machines, UART communication, PWM audio generation, and real-time seven-segment display output.

---

## Overview

This project demonstrates the design and implementation of a complete digital communication system on FPGA.

The transceiver operates in two independent modes:

* **Manual Decoder:** translates user button presses into Morse symbols and converts them into ASCII characters displayed locally and transmitted to a computer through UART.
* **Automatic Encoder:** generates standard-compliant Morse code audio from a letter selected using the onboard switches.

The entire system is implemented in VHDL and runs on the Basys 3 development board using a 100 MHz system clock.

---

## Features

* Bidirectional Morse communication
* Manual Morse decoding
* Automatic Morse code generation
* UART transmission (9600 baud, 8N1)
* PWM audio output for buzzer
* Seven-segment display output
* LED timing visualization
* Software button debouncing
* Finite State Machine (FSM) based architecture
* Fully synthesizable VHDL implementation

---

## Hardware Platform

* Digilent Basys 3 FPGA Board
* Xilinx Artix-7 XC7A35T
* 100 MHz onboard oscillator
* Optional buzzer connected to PMOD JA
* USB-UART interface for serial communication

---

## System Architecture

```
                +--------------------+
                |    Push Button     |
                +---------+----------+
                          |
                    Pulse Analyzer
                          |
                    Morse Decoder FSM
                          |
              +-----------+------------+
              |                        |
      7-Segment Display          UART Transmitter
              |                        |
              |                  PC Terminal
              |
      Display Buffer

Switches
    |
    v
Auto Encoder FSM
    |
PWM Generator
    |
Buzzer
```

---

## Operating Modes

### Manual Decoder

The center push button is used to input Morse code manually.

* Short press → Dot (`.`)
* Long press → Dash (`-`)
* Pause → End of character

The decoded character is:

* displayed on the seven-segment display
* transmitted over UART
* stored in a scrolling four-character buffer

LEDs provide real-time visual feedback during button presses to help distinguish dots from dashes.

---

### Automatic Encoder

A character is selected using the five onboard switches.

After pressing the trigger button, the FPGA automatically generates the corresponding Morse sequence.

The encoder respects the international Morse timing standard:

* Dot = 1 unit
* Dash = 3 units
* Symbol spacing = 1 unit

Audio is generated using a PWM square-wave signal.

---

## UART Communication

Decoded characters are transmitted through the onboard USB-UART interface using:

| Parameter | Value |
| --------- | ----- |
| Baud Rate | 9600  |
| Data Bits | 8     |
| Parity    | None  |
| Stop Bits | 1     |

The output can be monitored using software such as PuTTY or Tera Term.

---

## Repository Structure

```
fpga-morse-code-transceiver/
│
├── README.md
├── LICENSE
├── .gitignore
│
├── src/
│   ├── MorseSystem.vhd
│   └── Basys3.xdc
│
├── docs/
│   ├── Project_Specification.pdf
│   └── User_Manual.pdf
│
├── images/
│   └── morse-alphabet.png
│
└── demo/
```

---

## Getting Started

### Requirements

* Xilinx Vivado
* Digilent Basys 3 FPGA
* Micro-USB cable
* Optional buzzer connected to PMOD JA

### Build

1. Create a new Vivado project.
2. Add `MorseSystem.vhd`.
3. Add `Basys3.xdc`.
4. Run synthesis and implementation.
5. Generate the bitstream.
6. Program the Basys 3 board.

---

## Demonstration

### Decoder

* Press the center button using Morse timing.
* Wait briefly after each character.
* Observe:

  * Seven-segment display
  * UART terminal output
  * LED timing indicator

### Encoder

* Select a letter using switches.
* Press the upper button.
* Listen to the generated Morse code through the buzzer.

---

## Future Improvements

* Support numbers and punctuation
* Adjustable Morse transmission speed
* Complete bidirectional UART communication
* LCD/OLED display support
* Morse message recording and playback
* Error detection for invalid sequences

---

## Documentation

Additional documentation is available in the `docs/` directory:

* Project Specification
* User Manual

---

## License

This project is released under the MIT License.

---

## Author

**Anas Saoudi**

ICT Engineering Student

Interested in Digital Design, Embedded Systems, FPGA Development, and Artificial Intelligence.
