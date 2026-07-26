#ifndef BGI_WINE_BRIDGE_PROTOCOL_H
#define BGI_WINE_BRIDGE_PROTOCOL_H

#include <stdint.h>

#define BGI_WINE_BRIDGE_MAGIC UINT32_C(0x31494742)
#define BGI_WINE_BRIDGE_VERSION UINT16_C(2)
#define BGI_WINE_BRIDGE_MAX_PAYLOAD UINT32_C(65536)
#define BGI_WINE_INPUT_MARKER UINT64_C(0x42474957494E45)

#define BGI_WINE_CAP_KEYBOARD UINT32_C(1)
#define BGI_WINE_CAP_MOUSE UINT32_C(1 << 1)
#define BGI_WINE_CAP_RELATIVE_MOUSE UINT32_C(1 << 2)
#define BGI_WINE_CAP_TEXT UINT32_C(1 << 3)
#define BGI_WINE_CAP_STATE_QUERY UINT32_C(1 << 4)
#define BGI_WINE_CAP_TARGET_DISCOVERY UINT32_C(1 << 5)
#define BGI_WINE_CAP_FOREGROUND_DIAGNOSTICS UINT32_C(1 << 6)
#define BGI_WINE_CAP_INPUT_CONTEXT_PRIMING UINT32_C(1 << 7)
#define BGI_WINE_CAP_ATOMIC_INPUT_CONTEXT UINT32_C(1 << 8)

#define BGI_WINE_DIAGNOSTIC_TARGET_IS_WINDOW UINT32_C(1)
#define BGI_WINE_DIAGNOSTIC_TARGET_IS_VISIBLE UINT32_C(1 << 1)

enum bgi_wine_command {
    BGI_WINE_COMMAND_HELLO = 1,
    BGI_WINE_COMMAND_AUTHENTICATE = 2,
    BGI_WINE_COMMAND_DISCOVER_TARGET = 3,
    BGI_WINE_COMMAND_REGISTER_TARGET = 4,
    BGI_WINE_COMMAND_PING = 5,
    BGI_WINE_COMMAND_QUERY_FOREGROUND = 6,
    BGI_WINE_COMMAND_SET_FOREGROUND = 7,
    BGI_WINE_COMMAND_PREPARE_TARGET_INPUT = 8,
    BGI_WINE_COMMAND_PRIME_TARGET_INPUT = 9,
    BGI_WINE_COMMAND_KEY_DOWN = 10,
    BGI_WINE_COMMAND_KEY_UP = 11,
    BGI_WINE_COMMAND_KEY_PRESS = 12,
    BGI_WINE_COMMAND_MOUSE_BUTTON_DOWN = 20,
    BGI_WINE_COMMAND_MOUSE_BUTTON_UP = 21,
    BGI_WINE_COMMAND_MOUSE_CLICK = 22,
    BGI_WINE_COMMAND_MOUSE_MOVE_ABSOLUTE = 23,
    BGI_WINE_COMMAND_MOUSE_MOVE_RELATIVE = 24,
    BGI_WINE_COMMAND_MOUSE_WHEEL = 25,
    BGI_WINE_COMMAND_INPUT_TEXT = 30,
    BGI_WINE_COMMAND_QUERY_KEY_STATE = 40,
    BGI_WINE_COMMAND_QUERY_MOUSE_BUTTON_STATE = 41,
    BGI_WINE_COMMAND_RELEASE_ALL = 50,
    BGI_WINE_COMMAND_SHUTDOWN = 51,
    BGI_WINE_COMMAND_CONFIGURE_INPUT_CONTEXT = 52
};

enum bgi_wine_status {
    BGI_WINE_STATUS_OK = 0,
    BGI_WINE_STATUS_INVALID_HEADER = 1,
    BGI_WINE_STATUS_UNSUPPORTED_VERSION = 2,
    BGI_WINE_STATUS_UNSUPPORTED_COMMAND = 3,
    BGI_WINE_STATUS_AUTHENTICATION_REQUIRED = 4,
    BGI_WINE_STATUS_AUTHENTICATION_FAILED = 5,
    BGI_WINE_STATUS_ALREADY_AUTHENTICATED = 6,
    BGI_WINE_STATUS_INVALID_PAYLOAD = 7,
    BGI_WINE_STATUS_TARGET_REQUIRED = 8,
    BGI_WINE_STATUS_TARGET_NOT_FOUND = 9,
    BGI_WINE_STATUS_TARGET_MISMATCH = 10,
    BGI_WINE_STATUS_INPUT_FAILED = 11,
    BGI_WINE_STATUS_INTERNAL_ERROR = 12,
    BGI_WINE_STATUS_INPUT_CONTEXT_PRIMING_REQUIRED = 13
};

enum bgi_wine_mouse_button {
    BGI_WINE_MOUSE_LEFT = 1,
    BGI_WINE_MOUSE_RIGHT = 2,
    BGI_WINE_MOUSE_MIDDLE = 3,
    BGI_WINE_MOUSE_X1 = 4,
    BGI_WINE_MOUSE_X2 = 5
};

enum bgi_wine_modifiers {
    BGI_WINE_MODIFIER_SHIFT = 1,
    BGI_WINE_MODIFIER_CONTROL = 1 << 1,
    BGI_WINE_MODIFIER_ALT = 1 << 2
};

#pragma pack(push, 1)
struct bgi_wine_packet_header {
    uint32_t magic;
    uint16_t version;
    uint16_t command;
    uint32_t request_id;
    uint32_t payload_length;
    uint32_t status;
    uint32_t reserved;
};

struct bgi_wine_hello_response {
    uint16_t protocol_version;
    uint16_t reserved;
    uint32_t capabilities;
    uint64_t input_marker;
};

struct bgi_wine_target {
    uint32_t process_id;
    uint32_t reserved;
    uint64_t window_handle;
    char executable_name[64];
};

struct bgi_wine_key {
    uint16_t virtual_key;
    uint16_t modifiers;
    uint32_t duration_ms;
};

struct bgi_wine_mouse_button_payload {
    uint8_t button;
    uint8_t move_first;
    uint16_t reserved;
    /* Target HWND client coordinates when move_first is set. */
    int32_t x;
    int32_t y;
    uint32_t duration_ms;
};

struct bgi_wine_mouse_move {
    /* Target HWND client coordinates for absolute moves; signed delta otherwise. */
    int32_t x;
    int32_t y;
};

struct bgi_wine_mouse_wheel {
    int32_t delta;
};

struct bgi_wine_query_key {
    uint16_t virtual_key;
    uint16_t reserved;
};

struct bgi_wine_query_mouse {
    uint8_t button;
    uint8_t reserved[3];
};

struct bgi_wine_query_response {
    uint8_t is_down;
    uint8_t reserved[3];
};

struct bgi_wine_input_context_policy {
    uint8_t enabled;
    uint8_t maximum_attempts;
    uint16_t retry_delay_ms;
};

struct bgi_wine_foreground_diagnostic {
    uint32_t target_process_id;
    uint32_t foreground_process_id;
    uint32_t target_thread_id;
    uint32_t foreground_thread_id;
    uint64_t target_window;
    uint64_t foreground_window;
    uint64_t active_window;
    uint64_t focus_window;
    uint64_t capture_window;
    uint64_t menu_owner_window;
    uint64_t move_size_window;
    int32_t set_foreground_result;
    uint32_t flags;
    uint16_t test_virtual_key;
    uint16_t async_key_state;
    char foreground_executable_name[64];
};
#pragma pack(pop)

#endif
