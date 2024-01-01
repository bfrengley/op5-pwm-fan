Orange Pi 5 PWM Fan Controller
==============================

This repository implements a fan speed controller for a PWM fan connected to an [Orange Pi 5 SBC](http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/details/Orange-Pi-5.html). The controller runs as a long-running service which enables a PWM pin, periodically checks the SoC thermal zone's temperature, and updates the fan duty cycle. The fan is off below 50C and runs at full speed above 75C; between these two temperatures its duty cycle scales linearly.

This controller has been tested only using [Armbian](https://www.armbian.com/orangepi-5/) and a Noctua [NF-A4x20 5V PWM fan](https://noctua.at/en/products/fan/nf-a4x20-5v-pwm).

The controller uses the following defaults:
- PWM pin: [PWM15_IR_M2](http://www.orangepi.org/orangepiwiki/index.php/26_Pin_Interface_Pin_Description)
- PWM frequency: 25kHz
    - This is the required frequency for Noctua PWM fans, as specified in their [whitepaper](https://noctua.at/pub/media/wysiwyg/Noctua_PWM_specifications_white_paper.pdf)
    - Since PWM periods and duty cycles are specified in nanoseconds, this corresponds to a period of 40,000ns
- Thermal zone: 0 (SoC temperature)

## Installation

Requirements:
- [Zig](https://ziglang.org/)
- The PWM overlay for the PWM pin you want to use must be enabled
    - In Armbian, this can be enabled using `armbian-config`:
        1. Run `sudo armbian-config`
        2. Select `System`
        3. Select `Hardware`
        4. Find the PWM pin you want to use (e.g., the default pin is `rk3588-pwm15-m2`) and select it using Space
        5. Select `Save`
        6. Save, exit, and reboot the Orange Pi.
- SSH access to the Orange Pi if building and installing from another computer
- A 5V PWM fan connected to ground, 5V, and PWM15 (or another PWM pin)

1. Compile the binary. This can be done from another computer using Zig's cross compilation support:
    ```bash
    zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSafe
    ```

    The binary will now be at `zig-out/bin/op5-pwm-fan`.

2. Copy the binary and systemd unit to the appropriate places on the Orange Pi 5. If you are using
    another computer, this can be done using `scp` or any other appropriate tool.
    - `zig-out/bin/op5-pwm-fan` -> `/usr/bin/op5-pwm-fan`
    - `fan-controller.service` -> `/etc/systemd/system/fan-controller.service`

3. Run `sudo systemctl daemon-reload` to allow systemd to find the unit

4. Enable and start the fan controller:
    ```bash
    sudo systemctl start fan-controller.service
    sudo systemctl enable fan-controller.service
    ```

Your fan should now automatically adjust its speed as the temperature of your device changes.

## License

This repository is licensed under the [MIT license](LICENSE).
