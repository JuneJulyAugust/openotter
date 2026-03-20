#include <iostream>
#include <string>
#include <vector>
#include <chrono>
#include <mutex>
#include <thread>
#include <iomanip>
#include <asio.hpp>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>

#include <ftxui/dom/elements.hpp>
#include <ftxui/screen/screen.hpp>
#include <ftxui/component/component.hpp>
#include <ftxui/component/screen_interactive.hpp>

using namespace ftxui;
using asio::ip::udp;

struct MCPStatus {
    std::string pi_name = "metalbot-mcp (Pi 4B)";
    std::string pi_ip = "192.168.2.189";
    std::string iphone_name = "Waiting for Brain...";
    std::string iphone_ip = "0.0.0.0";
    
    std::string last_received_time = "--:--:--";
    std::string last_sent_time = "--:--:--";
    std::chrono::steady_clock::time_point last_rx_tp;
    
    int hb_received = 0;
    int hb_sent = 0;
    int cmd_received = 0;
    
    std::string last_command = "No data";
    bool connected = false;
    float steering = 0.0f; 
    float motor = 0.0f;    
    
    // Serial state
    std::string serial_port_name = "/dev/ttyUSB0";
    bool serial_connected = false;
    std::string last_serial_ack = "None";
    
    udp::endpoint iphone_endpoint;
    std::mutex mtx;
};

MCPStatus status;

std::string get_current_time() {
    auto now = std::chrono::system_clock::now();
    auto now_t = std::chrono::system_clock::to_time_t(now);
    std::stringstream ss;
    ss << std::put_time(std::localtime(&now_t), "%H:%M:%S");
    return ss.str();
}

Element RenderMeter(std::string label, float value) {
    const int half_width = 20;
    int blocks = (int)(std::abs(value) * half_width);
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
            text(std::to_string((int)(value * 100)) + "%") | bold | color(meter_color),
            text(" ")
        }),
        hbox(Elements{
            left_side,
            separator() | color(Color::White),
            right_side
        }) | borderRounded | hcenter
    }) | flex;
}

void run_network_server() {
    try {
        asio::io_context io_context;
        udp::socket socket(io_context, udp::endpoint(udp::v4(), 8888));
        
        std::thread sender_thread([&]() {
            while (true) {
                std::this_thread::sleep_for(std::chrono::seconds(1));
                std::lock_guard<std::mutex> lock(status.mtx);
                if (status.iphone_endpoint.address().to_string() != "0.0.0.0") {
                    std::string msg = "hb_pi:" + std::to_string(status.hb_sent);
                    socket.send_to(asio::buffer(msg), status.iphone_endpoint);
                    status.hb_sent++;
                    status.last_sent_time = get_current_time();
                }
            }
        });
        sender_thread.detach();

        while (true) {
            char data[1024];
            udp::endpoint remote_endpoint;
            size_t length = socket.receive_from(asio::buffer(data), remote_endpoint);
            
            std::string message(data, length);
            std::lock_guard<std::mutex> lock(status.mtx);
            status.iphone_endpoint = remote_endpoint;
            status.iphone_ip = remote_endpoint.address().to_string();
            status.last_received_time = get_current_time();
            status.last_rx_tp = std::chrono::steady_clock::now();
            status.connected = true;
            
            if (message.find("hb_iphone:") == 0) {
                status.hb_received++;
                status.iphone_name = "metalbot-brain (iPhone)";
            } else if (message.find("cmd:") == 0) {
                status.cmd_received++;
                status.last_command = message;
                size_t s_pos = message.find("s=");
                size_t m_pos = message.find("m=");
                if (s_pos != std::string::npos) status.steering = std::stof(message.substr(s_pos+2));
                if (m_pos != std::string::npos) {
                    std::string m_part = message.substr(m_pos+2);
                    size_t comma = m_part.find(',');
                    status.motor = std::stof(m_part.substr(0, comma));
                }
            }
        }
    } catch (std::exception& e) {
        std::cerr << "Network Error: " << e.what() << std::endl;
    }
}

void run_serial_forwarder() {
    asio::io_context io;
    std::unique_ptr<asio::serial_port> serial;
    
    char read_buf[1024];
    std::string read_line;

    while (true) {
        try {
            if (!serial || !serial->is_open()) {
                // Check if device physically exists before trying to open
                if (access(status.serial_port_name.c_str(), F_OK) == -1) {
                    {
                        std::lock_guard<std::mutex> lock(status.mtx);
                        status.serial_connected = false;
                        status.last_serial_ack = "Waiting for USB device...";
                    }
                    std::this_thread::sleep_for(std::chrono::seconds(1));
                    continue;
                }

                serial = std::make_unique<asio::serial_port>(io, status.serial_port_name);
                serial->set_option(asio::serial_port_base::baud_rate(115200));
                
                int fd = serial->native_handle();
                int flags = fcntl(fd, F_GETFL, 0);
                fcntl(fd, F_SETFL, flags | O_NONBLOCK);

                {
                    std::lock_guard<std::mutex> lock(status.mtx);
                    status.serial_connected = true;
                    status.last_serial_ack = "Booting Arduino (3.5s)...";
                }
                
                // Wait for Arduino auto-reset and ESC arming
                std::this_thread::sleep_for(std::chrono::milliseconds(3500));
                
                // Flush stale junk data that arrived during boot
                tcflush(fd, TCIOFLUSH);

                {
                    std::lock_guard<std::mutex> lock(status.mtx);
                    status.last_serial_ack = "Arduino ready";
                }
            }
            
            float s, m;
            {
                std::lock_guard<std::mutex> lock(status.mtx);
                s = status.steering;
                m = status.motor;
            }
            
            std::stringstream ss;
            ss << std::fixed << std::setprecision(2) << "S:" << s << ",M:" << m << "\n";
            std::string cmd = ss.str();
            
            // Write with error code to catch disconnects immediately
            std::error_code ec;
            asio::write(*serial, asio::buffer(cmd), ec);
            if (ec) {
                throw std::runtime_error("Write failed: " + ec.message());
            }
            
            // Read feedback
            size_t len = serial->read_some(asio::buffer(read_buf, sizeof(read_buf)), ec);
            if (!ec && len > 0) {
                for (size_t i = 0; i < len; ++i) {
                    if (read_buf[i] == '\n') {
                        std::lock_guard<std::mutex> lock(status.mtx);
                        // Truncate if too long to prevent UI layout issues
                        if (read_line.length() > 40) read_line = read_line.substr(0, 40) + "...";
                        status.last_serial_ack = read_line;
                        read_line.clear();
                    } else if (read_buf[i] != '\r') {
                        read_line += read_buf[i];
                    }
                }
            } else if (ec && ec != asio::error::would_block && ec != asio::error::try_again) {
                throw std::runtime_error("Read failed: " + ec.message());
            }
            
            std::this_thread::sleep_for(std::chrono::milliseconds(50)); // 20Hz update rate
            
        } catch (std::exception& e) {
            {
                std::lock_guard<std::mutex> lock(status.mtx);
                status.serial_connected = false;
                status.last_serial_ack = std::string("Err: ") + e.what();
            }
            if (serial) {
                std::error_code ec;
                serial->close(ec);
                serial.reset();
            }
            std::this_thread::sleep_for(std::chrono::seconds(2));
        }
    }
}

int main() {
    std::thread net_thread(run_network_server);
    net_thread.detach();

    std::thread serial_thread(run_serial_forwarder);
    serial_thread.detach();

    auto screen = ScreenInteractive::Fullscreen();

    auto renderer = Renderer([&] {
        {
            std::lock_guard<std::mutex> lock(status.mtx);
            auto now = std::chrono::steady_clock::now();
            auto diff = std::chrono::duration_cast<std::chrono::seconds>(now - status.last_rx_tp).count();
            if (diff > 1.5) {
                status.connected = false;
            }
        }

        std::lock_guard<std::mutex> lock(status.mtx);
        
        auto header = vbox(Elements{
            hbox(Elements{
                text(" 🏎️  METALBOT MCP ") | bold | color(Color::White) | bgcolor(Color::Blue),
                filler(),
                text(" PI TIME: " + get_current_time() + " ") | color(Color::Yellow),
                separator(),
                text(" " + status.pi_name + " | " + status.pi_ip + " ") | color(Color::Cyan),
            }),
            separator()
        }) | border;

        auto brain_card = vbox(Elements{
            text(" 🧠 REMOTE BRAIN (iPhone) ") | bold | center,
            separator(),
            hbox(Elements{text(" Name: "), filler(), text(status.iphone_name)}),
            hbox(Elements{text(" IP:   "), filler(), text(status.iphone_ip) | color(Color::Cyan)}),
            hbox(Elements{text(" Status: "), filler(), text(status.connected ? "CONNECTED" : "OFFLINE") | color(status.connected ? Color::Green : Color::Red)}),
        }) | borderLight | flex;

        auto comms_card = vbox(Elements{
            text(" 📶 COMMUNICATION METRICS ") | bold | center,
            separator(),
            hbox(Elements{text(" HB Received: "), filler(), text(std::to_string(status.hb_received)) | color(Color::Green)}),
            hbox(Elements{text(" HB Sent:     "), filler(), text(std::to_string(status.hb_sent)) | color(Color::Yellow)}),
            hbox(Elements{text(" CMD Received: "), filler(), text(std::to_string(status.cmd_received)) | color(Color::Magenta) | bold}),
            hbox(Elements{text(" Last Rx:     "), filler(), text(status.last_received_time)}),
        }) | borderLight | flex;

        auto arduino_card = vbox(Elements{
            text(" 🔌 ARDUINO CONTROL ") | bold | center,
            separator(),
            hbox(Elements{text(" Port: "), filler(), text(status.serial_port_name)}),
            hbox(Elements{text(" Serial: "), filler(), text(status.serial_connected ? "CONNECTED" : "DISCONNECTED") | color(status.serial_connected ? Color::Green : Color::Red)}),
            hbox(Elements{text(" Feedback: "), filler(), text(status.last_serial_ack) | dim}),
        }) | borderLight | flex;

        auto dashboard = hbox(Elements{
            RenderMeter("STEERING", status.steering),
            RenderMeter("MOTOR POWER", status.motor),
        });

        return vbox(Elements{
            header,
            hbox(Elements{ brain_card, comms_card, arduino_card }),
            dashboard | size(HEIGHT, EQUAL, 8),
            hbox(Elements{
                text(" Last CMD: " + status.last_command) | dim,
                filler(),
                text(" PRESS 'Q' TO SHUTDOWN ") | dim | blink,
            })
        });
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

    return 0;
}
