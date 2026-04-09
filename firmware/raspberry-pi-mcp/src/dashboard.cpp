#include "dashboard.h"

#include "protocol.h"

#include <cmath>
#include <string>
#include <thread>

#include <ftxui/component/component.hpp>
#include <ftxui/component/screen_interactive.hpp>
#include <ftxui/dom/elements.hpp>
#include <ftxui/screen/screen.hpp>

using namespace ftxui;

namespace raspberry_pi_mcp {

namespace {

Element RenderMeter(const std::string& label, float value) {
    const int half_width = 20;
    int blocks = static_cast<int>(std::abs(value) * half_width);
    auto meter_color = (value < 0) ? Color::Blue : (value > 0 ? Color::Green : Color::White);

    auto left_side = hbox(Elements{
        filler(),
        (value < 0) ? text(std::string(blocks, ' ')) | bgcolor(Color::Blue) : text("")
    }) | size(WIDTH, EQUAL, half_width);

    auto right_side = hbox(Elements{
        (value > 0) ? text(std::string(blocks, ' ')) | bgcolor(Color::Green) : text(""),
        filler()
    }) | size(WIDTH, EQUAL, half_width);

    return vbox(Elements{
        hbox(Elements{
            text(" " + label) | bold,
            filler(),
            text(std::to_string(static_cast<int>(value * 100)) + "%") | bold | color(meter_color),
            text(" ")
        }),
        hbox(Elements{
            left_side,
            separator() | color(Color::White),
            right_side
        }) | borderRounded | hcenter
    }) | flex;
}

Element RenderDashboard(const StatusSnapshot& s) {
    auto header = vbox(Elements{
        hbox(Elements{
            text(" 🏎️  OPENOTTER MCP ") | bold | color(Color::White) | bgcolor(Color::Blue),
            filler(),
            text(" PI TIME: " + getCurrentTime() + " ") | color(Color::Yellow),
            separator(),
            text(" " + s.pi_name + " | " + s.pi_ip + " ") | color(Color::Cyan),
        }),
        separator()
    }) | border;

    auto brain_card = vbox(Elements{
        text(" 🧠 REMOTE BRAIN (iPhone) ") | bold | center,
        separator(),
        hbox(Elements{text(" Name: "), filler(), text(s.iphone_name)}),
        hbox(Elements{text(" IP:   "), filler(), text(s.iphone_ip) | color(Color::Cyan)}),
        hbox(Elements{text(" Status: "), filler(),
            text(s.connected ? "CONNECTED" : "OFFLINE") |
            color(s.connected ? Color::Green : Color::Red)}),
    }) | borderLight | flex;

    auto comms_card = vbox(Elements{
        text(" 📶 COMMUNICATION METRICS ") | bold | center,
        separator(),
        hbox(Elements{text(" HB Received: "), filler(),
            text(std::to_string(s.hb_received)) | color(Color::Green)}),
        hbox(Elements{text(" HB Sent:     "), filler(),
            text(std::to_string(s.hb_sent)) | color(Color::Yellow)}),
        hbox(Elements{text(" CMD Received: "), filler(),
            text(std::to_string(s.cmd_received)) | color(Color::Magenta) | bold}),
        hbox(Elements{text(" Last Rx:     "), filler(), text(s.last_received_time)}),
    }) | borderLight | flex;

    auto arduino_card = vbox(Elements{
        text(" 🔌 ARDUINO CONTROL ") | bold | center,
        separator(),
        hbox(Elements{text(" Port: "), filler(), text(s.serial_port_name)}),
        hbox(Elements{text(" Serial: "), filler(),
            text(s.serial_connected ? "CONNECTED" : "DISCONNECTED") |
            color(s.serial_connected ? Color::Green : Color::Red)}),
        hbox(Elements{text(" Feedback: "), filler(), text(s.last_serial_ack) | dim}),
    }) | borderLight | flex;

    auto dashboard = hbox(Elements{
        RenderMeter("STEERING", s.steering),
        RenderMeter("MOTOR POWER", s.motor),
    });

    return vbox(Elements{
        header,
        hbox(Elements{ brain_card, comms_card, arduino_card }),
        dashboard | size(HEIGHT, EQUAL, 8),
        hbox(Elements{
            text(" Last CMD: " + s.last_command) | dim,
            filler(),
            text(" PRESS 'Q' TO SHUTDOWN ") | dim | blink,
        })
    });
}

}  // namespace

void runDashboard(MCPStatus& status) {
    auto screen = ScreenInteractive::Fullscreen();

    auto renderer = Renderer([&] {
        status.refreshConnectionState();
        StatusSnapshot s = status.snapshot();
        return RenderDashboard(s);
    });

    auto component = CatchEvent(renderer, [&](Event event) {
        if (event == Event::Character('q') || event == Event::Character('Q')) {
            screen.Exit();
            return true;
        }
        return false;
    });

    std::thread refresh_thread([&] {
        while (true) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            screen.PostEvent(Event::Custom);
        }
    });
    refresh_thread.detach();

    screen.Loop(component);
}

}  // namespace raspberry_pi_mcp
