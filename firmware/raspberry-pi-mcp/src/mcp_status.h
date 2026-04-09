#pragma once

#include "protocol.h"

#include <chrono>
#include <mutex>
#include <string>

#include <asio.hpp>

namespace raspberry-pi-mcp {

/// Immutable snapshot of system state for rendering.
/// Captured under lock, consumed without holding any mutex.
struct StatusSnapshot {
    std::string pi_name = "raspberry-pi-mcp (Pi 4B)";
    std::string pi_ip = "192.168.2.189";
    std::string iphone_name = "Waiting for Brain...";
    std::string iphone_ip = "0.0.0.0";

    std::string last_received_time = "--:--:--";
    std::string last_sent_time = "--:--:--";

    int hb_received = 0;
    int hb_sent = 0;
    int cmd_received = 0;

    std::string last_command = "No data";
    bool connected = false;
    float steering = 0.0f;
    float motor = 0.0f;

    std::string serial_port_name = "/dev/ttyUSB0";
    bool serial_connected = false;
    std::string last_serial_ack = "None";
};

/// Thread-safe status container.
/// Writers call mutation methods (auto-locked).
/// Readers call snapshot() to get a consistent copy.
class MCPStatus {
public:
    explicit MCPStatus(std::string serial_port = "/dev/ttyUSB0")
        : serial_port_name_(std::move(serial_port)) {}

    /// Return a consistent snapshot for rendering.
    StatusSnapshot snapshot() const {
        std::lock_guard<std::mutex> lock(mtx_);
        StatusSnapshot s;
        s.iphone_name = iphone_name_;
        s.iphone_ip = iphone_ip_;
        s.last_received_time = last_received_time_;
        s.last_sent_time = last_sent_time_;
        s.hb_received = hb_received_;
        s.hb_sent = hb_sent_;
        s.cmd_received = cmd_received_;
        s.last_command = last_command_;
        s.connected = connected_;
        s.steering = steering_;
        s.motor = motor_;
        s.serial_port_name = serial_port_name_;
        s.serial_connected = serial_connected_;
        s.last_serial_ack = last_serial_ack_;
        return s;
    }

    // -- Network writers --

    void recordHeartbeatReceived(const std::string& time) {
        std::lock_guard<std::mutex> lock(mtx_);
        hb_received_++;
        last_received_time_ = time;
        last_rx_tp_ = std::chrono::steady_clock::now();
        connected_ = true;
        iphone_name_ = "openotter-brain (iPhone)";
    }

    void recordHeartbeatSent(const std::string& time) {
        std::lock_guard<std::mutex> lock(mtx_);
        hb_sent_++;
        last_sent_time_ = time;
    }

    void recordCommandReceived(const ControlCommand& cmd, const std::string& raw) {
        std::lock_guard<std::mutex> lock(mtx_);
        cmd_received_++;
        last_command_ = raw;
        last_received_time_ = getCurrentTime();
        last_rx_tp_ = std::chrono::steady_clock::now();
        connected_ = true;
        steering_ = cmd.steering;
        motor_ = cmd.motor;
    }

    void setRemoteEndpoint(const asio::ip::udp::endpoint& ep) {
        std::lock_guard<std::mutex> lock(mtx_);
        iphone_endpoint_ = ep;
        iphone_ip_ = ep.address().to_string();
    }

    asio::ip::udp::endpoint remoteEndpoint() const {
        std::lock_guard<std::mutex> lock(mtx_);
        return iphone_endpoint_;
    }

    int heartbeatSentCount() const {
        std::lock_guard<std::mutex> lock(mtx_);
        return hb_sent_;
    }

    /// Check whether the connection has timed out (>1.5s since last Rx).
    void refreshConnectionState() {
        std::lock_guard<std::mutex> lock(mtx_);
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - last_rx_tp_).count();
        if (elapsed > 1500) {
            connected_ = false;
        }
    }

    // -- Serial writers --

    void setSerialState(bool connected, const std::string& ack) {
        std::lock_guard<std::mutex> lock(mtx_);
        serial_connected_ = connected;
        last_serial_ack_ = ack;
    }

    /// Read current control values for serial transmission.
    ControlCommand currentControl() const {
        std::lock_guard<std::mutex> lock(mtx_);
        return {steering_, motor_};
    }

    std::string serialPortName() const {
        std::lock_guard<std::mutex> lock(mtx_);
        return serial_port_name_;
    }

private:
    mutable std::mutex mtx_;

    // Network state
    std::string iphone_name_ = "Waiting for Brain...";
    std::string iphone_ip_ = "0.0.0.0";
    std::string last_received_time_ = "--:--:--";
    std::string last_sent_time_ = "--:--:--";
    std::chrono::steady_clock::time_point last_rx_tp_;
    int hb_received_ = 0;
    int hb_sent_ = 0;
    int cmd_received_ = 0;
    std::string last_command_ = "No data";
    bool connected_ = false;
    float steering_ = 0.0f;
    float motor_ = 0.0f;
    asio::ip::udp::endpoint iphone_endpoint_;

    // Serial state
    std::string serial_port_name_;
    bool serial_connected_ = false;
    std::string last_serial_ack_ = "None";
};

}  // namespace raspberry-pi-mcp
