#include "bgi_wine_bridge_protocol.h"

#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

struct bridge_state {
    SOCKET client;
    bool authenticated;
    bool shutting_down;
    char token[256];
    struct bgi_wine_target target;
    bool has_target;
    bool held_keys[256];
    bool held_mouse[6];
};

struct target_search {
    char executable_name[64];
    struct bgi_wine_target result;
    uint64_t best_area;
};

static bool receive_exact(SOCKET socket, void *buffer, size_t length)
{
    char *cursor = buffer;
    while (length > 0) {
        int received = recv(socket, cursor, (int)length, 0);
        if (received <= 0) return false;
        cursor += received;
        length -= (size_t)received;
    }
    return true;
}

static bool send_exact(SOCKET socket, const void *buffer, size_t length)
{
    const char *cursor = buffer;
    while (length > 0) {
        int sent = send(socket, cursor, (int)length, 0);
        if (sent <= 0) return false;
        cursor += sent;
        length -= (size_t)sent;
    }
    return true;
}

static bool send_response(
    SOCKET socket,
    const struct bgi_wine_packet_header *request,
    uint32_t status,
    const void *payload,
    uint32_t payload_length)
{
    struct bgi_wine_packet_header response = {
        BGI_WINE_BRIDGE_MAGIC,
        BGI_WINE_BRIDGE_VERSION,
        request->command,
        request->request_id,
        payload_length,
        status,
        0
    };
    return send_exact(socket, &response, sizeof(response))
        && (payload_length == 0 || send_exact(socket, payload, payload_length));
}

static bool constant_time_equals(const char *left, size_t left_length, const char *right)
{
    size_t right_length = strlen(right);
    unsigned char difference = (unsigned char)(left_length ^ right_length);
    size_t count = left_length > right_length ? left_length : right_length;
    for (size_t index = 0; index < count; ++index) {
        unsigned char left_value = index < left_length ? (unsigned char)left[index] : 0;
        unsigned char right_value = index < right_length ? (unsigned char)right[index] : 0;
        difference |= left_value ^ right_value;
    }
    return difference == 0;
}

static bool query_process_name(DWORD process_id, char *output, size_t output_size)
{
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
    if (process == NULL) return false;

    wchar_t wide_path[32768];
    DWORD path_length = (DWORD)(sizeof(wide_path) / sizeof(wide_path[0]));
    bool success = QueryFullProcessImageNameW(process, 0, wide_path, &path_length) != FALSE;
    CloseHandle(process);
    if (!success) return false;

    const wchar_t *basename = wcsrchr(wide_path, L'\\');
    basename = basename == NULL ? wide_path : basename + 1;
    int converted = WideCharToMultiByte(
        CP_UTF8, 0, basename, -1, output, (int)output_size, NULL, NULL);
    return converted > 0;
}

static bool executable_names_equal(const char *left, const char *right)
{
    return _stricmp(left, right) == 0;
}

static BOOL CALLBACK find_target_window(HWND window, LPARAM context)
{
    struct target_search *search = (struct target_search *)context;
    if (!IsWindowVisible(window)) return TRUE;

    DWORD process_id = 0;
    GetWindowThreadProcessId(window, &process_id);
    if (process_id == 0) return TRUE;

    char executable_name[64];
    if (!query_process_name(process_id, executable_name, sizeof(executable_name))
        || !executable_names_equal(executable_name, search->executable_name)) {
        return TRUE;
    }

    RECT rectangle;
    if (!GetWindowRect(window, &rectangle)) return TRUE;
    uint64_t width = rectangle.right > rectangle.left
        ? (uint64_t)(rectangle.right - rectangle.left) : 0;
    uint64_t height = rectangle.bottom > rectangle.top
        ? (uint64_t)(rectangle.bottom - rectangle.top) : 0;
    uint64_t area = width * height;
    if (area <= search->best_area) return TRUE;

    search->best_area = area;
    search->result.process_id = process_id;
    search->result.window_handle = (uint64_t)(uintptr_t)window;
    strncpy(search->result.executable_name, executable_name,
        sizeof(search->result.executable_name) - 1);
    search->result.executable_name[sizeof(search->result.executable_name) - 1] = '\0';
    return TRUE;
}

static bool discover_target(const char *name, size_t name_length, struct bgi_wine_target *target)
{
    if (name_length == 0 || name_length >= sizeof(target->executable_name)) return false;
    struct target_search search = {0};
    memcpy(search.executable_name, name, name_length);
    search.executable_name[name_length] = '\0';
    EnumWindows(find_target_window, (LPARAM)&search);
    if (search.result.window_handle == 0) return false;
    *target = search.result;
    return true;
}

static bool validate_target(const struct bgi_wine_target *target)
{
    HWND window = (HWND)(uintptr_t)target->window_handle;
    if (!IsWindow(window)) return false;

    DWORD process_id = 0;
    GetWindowThreadProcessId(window, &process_id);
    if (process_id != target->process_id) return false;

    char executable_name[64];
    return query_process_name(process_id, executable_name, sizeof(executable_name))
        && executable_names_equal(executable_name, target->executable_name);
}

static bool send_inputs(INPUT *inputs, UINT count)
{
    for (UINT index = 0; index < count; ++index) {
        if (inputs[index].type == INPUT_KEYBOARD) {
            inputs[index].ki.dwExtraInfo = (ULONG_PTR)BGI_WINE_INPUT_MARKER;
        } else if (inputs[index].type == INPUT_MOUSE) {
            inputs[index].mi.dwExtraInfo = (ULONG_PTR)BGI_WINE_INPUT_MARKER;
        }
    }
    return SendInput(count, inputs, sizeof(INPUT)) == count;
}

static bool send_key(struct bridge_state *state, WORD virtual_key, bool down)
{
    INPUT input = {0};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = virtual_key;
    input.ki.dwFlags = down ? 0 : KEYEVENTF_KEYUP;
    if (!send_inputs(&input, 1)) return false;
    if (virtual_key < 256) state->held_keys[virtual_key] = down;
    return true;
}

static const WORD modifier_keys[] = {VK_LSHIFT, VK_LCONTROL, VK_LMENU};
static const uint16_t modifier_flags[] = {
    BGI_WINE_MODIFIER_SHIFT,
    BGI_WINE_MODIFIER_CONTROL,
    BGI_WINE_MODIFIER_ALT
};

static bool press_modifiers(
    struct bridge_state *state,
    uint16_t modifiers,
    bool temporary[3])
{
    for (size_t index = 0; index < 3; ++index) {
        temporary[index] = false;
        if ((modifiers & modifier_flags[index]) == 0) continue;
        if (state->held_keys[modifier_keys[index]]) continue;
        if (!send_key(state, modifier_keys[index], true)) return false;
        temporary[index] = true;
    }
    return true;
}

static bool release_temporary_modifiers(
    struct bridge_state *state,
    const bool temporary[3])
{
    bool success = true;
    for (size_t offset = 0; offset < 3; ++offset) {
        size_t index = 2 - offset;
        if (temporary[index] && !send_key(state, modifier_keys[index], false)) {
            success = false;
        }
    }
    return success;
}

static bool release_requested_modifiers(
    struct bridge_state *state,
    uint16_t modifiers)
{
    bool success = true;
    for (size_t offset = 0; offset < 3; ++offset) {
        size_t index = 2 - offset;
        if ((modifiers & modifier_flags[index]) != 0
            && state->held_keys[modifier_keys[index]]
            && !send_key(state, modifier_keys[index], false)) {
            success = false;
        }
    }
    return success;
}

static bool perform_key(
    struct bridge_state *state,
    uint16_t command,
    const struct bgi_wine_key *key)
{
    if (key->virtual_key == 0 || key->virtual_key >= 256) return false;
    bool temporary[3] = {false, false, false};
    switch (command) {
    case BGI_WINE_COMMAND_KEY_DOWN:
        if (!press_modifiers(state, key->modifiers, temporary)) return false;
        if (send_key(state, key->virtual_key, true)) return true;
        release_temporary_modifiers(state, temporary);
        return false;
    case BGI_WINE_COMMAND_KEY_UP:
        if (!send_key(state, key->virtual_key, false)) return false;
        return release_requested_modifiers(state, key->modifiers);
    case BGI_WINE_COMMAND_KEY_PRESS:
        if (!press_modifiers(state, key->modifiers, temporary)
            || !send_key(state, key->virtual_key, true)) {
            release_temporary_modifiers(state, temporary);
            return false;
        }
        if (key->duration_ms > 0) Sleep(key->duration_ms > 10000 ? 10000 : key->duration_ms);
        return send_key(state, key->virtual_key, false)
            && release_temporary_modifiers(state, temporary);
    default:
        return false;
    }
}

static bool mouse_button_flags(
    uint8_t button,
    bool down,
    DWORD *flags,
    DWORD *mouse_data)
{
    *mouse_data = 0;
    switch (button) {
    case BGI_WINE_MOUSE_LEFT:
        *flags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
        return true;
    case BGI_WINE_MOUSE_RIGHT:
        *flags = down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
        return true;
    case BGI_WINE_MOUSE_MIDDLE:
        *flags = down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
        return true;
    case BGI_WINE_MOUSE_X1:
        *flags = down ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP;
        *mouse_data = XBUTTON1;
        return true;
    case BGI_WINE_MOUSE_X2:
        *flags = down ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP;
        *mouse_data = XBUTTON2;
        return true;
    default:
        return false;
    }
}

static bool send_mouse_button(struct bridge_state *state, uint8_t button, bool down)
{
    DWORD flags;
    DWORD mouse_data;
    if (!mouse_button_flags(button, down, &flags, &mouse_data)) return false;
    INPUT input = {0};
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = flags;
    input.mi.mouseData = mouse_data;
    if (!send_inputs(&input, 1)) return false;
    state->held_mouse[button] = down;
    return true;
}

static bool move_mouse_absolute(
    const struct bridge_state *state,
    int32_t client_x,
    int32_t client_y)
{
    RECT client_rect;
    if (!GetClientRect((HWND)(uintptr_t)state->target.window_handle, &client_rect)) return false;
    if (client_x < client_rect.left || client_x >= client_rect.right
        || client_y < client_rect.top || client_y >= client_rect.bottom) {
        return false;
    }

    POINT screen_point = {client_x, client_y};
    if (!ClientToScreen((HWND)(uintptr_t)state->target.window_handle, &screen_point)) return false;

    int left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (width <= 1 || height <= 1) return false;

    LONG normalized_x =
        (LONG)(((int64_t)(screen_point.x - left) * 65535) / (width - 1));
    LONG normalized_y =
        (LONG)(((int64_t)(screen_point.y - top) * 65535) / (height - 1));
    INPUT input = {0};
    input.type = INPUT_MOUSE;
    input.mi.dx = normalized_x;
    input.mi.dy = normalized_y;
    input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE
        | MOUSEEVENTF_VIRTUALDESK | MOUSEEVENTF_MOVE_NOCOALESCE;
    return send_inputs(&input, 1);
}

static bool move_mouse_relative(int32_t delta_x, int32_t delta_y)
{
    INPUT input = {0};
    input.type = INPUT_MOUSE;
    input.mi.dx = delta_x;
    input.mi.dy = delta_y;
    input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_MOVE_NOCOALESCE;
    return send_inputs(&input, 1);
}

static bool perform_mouse_button(
    struct bridge_state *state,
    uint16_t command,
    const struct bgi_wine_mouse_button_payload *payload)
{
    if (payload->button < BGI_WINE_MOUSE_LEFT || payload->button > BGI_WINE_MOUSE_X2) {
        return false;
    }
    if (payload->move_first
        && !move_mouse_absolute(state, payload->x, payload->y)) return false;

    switch (command) {
    case BGI_WINE_COMMAND_MOUSE_BUTTON_DOWN:
        return send_mouse_button(state, payload->button, true);
    case BGI_WINE_COMMAND_MOUSE_BUTTON_UP:
        return send_mouse_button(state, payload->button, false);
    case BGI_WINE_COMMAND_MOUSE_CLICK:
        if (!send_mouse_button(state, payload->button, true)) return false;
        if (payload->duration_ms > 0) {
            Sleep(payload->duration_ms > 10000 ? 10000 : payload->duration_ms);
        }
        return send_mouse_button(state, payload->button, false);
    default:
        return false;
    }
}

static bool input_text(struct bridge_state *state, const uint8_t *payload, uint32_t length)
{
    (void)state;
    if (length == 0 || (length % sizeof(uint16_t)) != 0) return false;
    for (uint32_t offset = 0; offset < length; offset += 2) {
        uint16_t code_unit = (uint16_t)(payload[offset] | (payload[offset + 1] << 8));
        INPUT inputs[2] = {0};
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].ki.wScan = code_unit;
        inputs[0].ki.dwFlags = KEYEVENTF_UNICODE;
        inputs[1] = inputs[0];
        inputs[1].ki.dwFlags |= KEYEVENTF_KEYUP;
        if (!send_inputs(inputs, 2)) return false;
    }
    return true;
}

static bool release_all(struct bridge_state *state)
{
    bool success = true;
    for (unsigned int virtual_key = 1; virtual_key < 256; ++virtual_key) {
        if (state->held_keys[virtual_key]
            && !send_key(state, (WORD)virtual_key, false)) {
            success = false;
        }
    }
    for (uint8_t button = BGI_WINE_MOUSE_LEFT; button <= BGI_WINE_MOUSE_X2; ++button) {
        if (state->held_mouse[button] && !send_mouse_button(state, button, false)) {
            success = false;
        }
    }
    return success;
}

static bool command_requires_target(uint16_t command)
{
    return command >= BGI_WINE_COMMAND_KEY_DOWN
        && command <= BGI_WINE_COMMAND_QUERY_MOUSE_BUTTON_STATE;
}

static uint32_t handle_authenticated_command(
    struct bridge_state *state,
    const struct bgi_wine_packet_header *request,
    const uint8_t *payload,
    void *response_payload,
    uint32_t *response_length)
{
    if (command_requires_target(request->command)) {
        if (!state->has_target) return BGI_WINE_STATUS_TARGET_REQUIRED;
        if (!validate_target(&state->target)) {
            state->has_target = false;
            release_all(state);
            return BGI_WINE_STATUS_TARGET_MISMATCH;
        }
    }

    switch (request->command) {
    case BGI_WINE_COMMAND_DISCOVER_TARGET: {
        struct bgi_wine_target target = {0};
        if (!discover_target((const char *)payload, request->payload_length, &target)) {
            return BGI_WINE_STATUS_TARGET_NOT_FOUND;
        }
        memcpy(response_payload, &target, sizeof(target));
        *response_length = sizeof(target);
        return BGI_WINE_STATUS_OK;
    }
    case BGI_WINE_COMMAND_REGISTER_TARGET:
        if (request->payload_length != sizeof(struct bgi_wine_target)) {
            return BGI_WINE_STATUS_INVALID_PAYLOAD;
        }
        memcpy(&state->target, payload, sizeof(state->target));
        state->target.executable_name[sizeof(state->target.executable_name) - 1] = '\0';
        if (!validate_target(&state->target)) return BGI_WINE_STATUS_TARGET_MISMATCH;
        state->has_target = true;
        return BGI_WINE_STATUS_OK;
    case BGI_WINE_COMMAND_PING:
        return BGI_WINE_STATUS_OK;
    case BGI_WINE_COMMAND_KEY_DOWN:
    case BGI_WINE_COMMAND_KEY_UP:
    case BGI_WINE_COMMAND_KEY_PRESS:
        if (request->payload_length != sizeof(struct bgi_wine_key)) {
            return BGI_WINE_STATUS_INVALID_PAYLOAD;
        }
        return perform_key(state, request->command, (const struct bgi_wine_key *)payload)
            ? BGI_WINE_STATUS_OK : BGI_WINE_STATUS_INPUT_FAILED;
    case BGI_WINE_COMMAND_MOUSE_BUTTON_DOWN:
    case BGI_WINE_COMMAND_MOUSE_BUTTON_UP:
    case BGI_WINE_COMMAND_MOUSE_CLICK:
        if (request->payload_length != sizeof(struct bgi_wine_mouse_button_payload)) {
            return BGI_WINE_STATUS_INVALID_PAYLOAD;
        }
        return perform_mouse_button(
            state, request->command,
            (const struct bgi_wine_mouse_button_payload *)payload)
            ? BGI_WINE_STATUS_OK : BGI_WINE_STATUS_INPUT_FAILED;
    case BGI_WINE_COMMAND_MOUSE_MOVE_ABSOLUTE:
    case BGI_WINE_COMMAND_MOUSE_MOVE_RELATIVE: {
        if (request->payload_length != sizeof(struct bgi_wine_mouse_move)) {
            return BGI_WINE_STATUS_INVALID_PAYLOAD;
        }
        const struct bgi_wine_mouse_move *move = (const struct bgi_wine_mouse_move *)payload;
        bool success = request->command == BGI_WINE_COMMAND_MOUSE_MOVE_ABSOLUTE
            ? move_mouse_absolute(state, move->x, move->y)
            : move_mouse_relative(move->x, move->y);
        return success ? BGI_WINE_STATUS_OK : BGI_WINE_STATUS_INPUT_FAILED;
    }
    case BGI_WINE_COMMAND_MOUSE_WHEEL: {
        if (request->payload_length != sizeof(struct bgi_wine_mouse_wheel)) {
            return BGI_WINE_STATUS_INVALID_PAYLOAD;
        }
        const struct bgi_wine_mouse_wheel *wheel =
            (const struct bgi_wine_mouse_wheel *)payload;
        INPUT input = {0};
        input.type = INPUT_MOUSE;
        input.mi.dwFlags = MOUSEEVENTF_WHEEL;
        input.mi.mouseData = (DWORD)wheel->delta;
        return send_inputs(&input, 1)
            ? BGI_WINE_STATUS_OK : BGI_WINE_STATUS_INPUT_FAILED;
    }
    case BGI_WINE_COMMAND_INPUT_TEXT:
        return input_text(state, payload, request->payload_length)
            ? BGI_WINE_STATUS_OK : BGI_WINE_STATUS_INPUT_FAILED;
    case BGI_WINE_COMMAND_QUERY_KEY_STATE: {
        if (request->payload_length != sizeof(struct bgi_wine_query_key)) {
            return BGI_WINE_STATUS_INVALID_PAYLOAD;
        }
        const struct bgi_wine_query_key *query =
            (const struct bgi_wine_query_key *)payload;
        struct bgi_wine_query_response response = {
            (GetAsyncKeyState(query->virtual_key) & 0x8000) != 0,
            {0, 0, 0}
        };
        memcpy(response_payload, &response, sizeof(response));
        *response_length = sizeof(response);
        return BGI_WINE_STATUS_OK;
    }
    case BGI_WINE_COMMAND_QUERY_MOUSE_BUTTON_STATE: {
        if (request->payload_length != sizeof(struct bgi_wine_query_mouse)) {
            return BGI_WINE_STATUS_INVALID_PAYLOAD;
        }
        const struct bgi_wine_query_mouse *query =
            (const struct bgi_wine_query_mouse *)payload;
        static const int virtual_keys[] = {
            0, VK_LBUTTON, VK_RBUTTON, VK_MBUTTON, VK_XBUTTON1, VK_XBUTTON2
        };
        if (query->button < BGI_WINE_MOUSE_LEFT || query->button > BGI_WINE_MOUSE_X2) {
            return BGI_WINE_STATUS_INVALID_PAYLOAD;
        }
        struct bgi_wine_query_response response = {
            (GetAsyncKeyState(virtual_keys[query->button]) & 0x8000) != 0,
            {0, 0, 0}
        };
        memcpy(response_payload, &response, sizeof(response));
        *response_length = sizeof(response);
        return BGI_WINE_STATUS_OK;
    }
    case BGI_WINE_COMMAND_RELEASE_ALL:
        return release_all(state) ? BGI_WINE_STATUS_OK : BGI_WINE_STATUS_INPUT_FAILED;
    case BGI_WINE_COMMAND_SHUTDOWN:
        state->shutting_down = true;
        return release_all(state) ? BGI_WINE_STATUS_OK : BGI_WINE_STATUS_INPUT_FAILED;
    default:
        return BGI_WINE_STATUS_UNSUPPORTED_COMMAND;
    }
}

static bool serve_client(struct bridge_state *state)
{
    uint8_t *payload = malloc(BGI_WINE_BRIDGE_MAX_PAYLOAD);
    uint8_t *response_payload = malloc(BGI_WINE_BRIDGE_MAX_PAYLOAD);
    if (payload == NULL || response_payload == NULL) {
        free(payload);
        free(response_payload);
        return false;
    }

    while (!state->shutting_down) {
        struct bgi_wine_packet_header request;
        if (!receive_exact(state->client, &request, sizeof(request))) break;
        if (request.magic != BGI_WINE_BRIDGE_MAGIC
            || request.payload_length > BGI_WINE_BRIDGE_MAX_PAYLOAD
            || request.reserved != 0) {
            send_response(
                state->client, &request, BGI_WINE_STATUS_INVALID_HEADER, NULL, 0);
            break;
        }
        if (request.version != BGI_WINE_BRIDGE_VERSION) {
            send_response(
                state->client, &request, BGI_WINE_STATUS_UNSUPPORTED_VERSION, NULL, 0);
            break;
        }
        if (request.payload_length > 0
            && !receive_exact(state->client, payload, request.payload_length)) {
            break;
        }

        uint32_t status = BGI_WINE_STATUS_OK;
        uint32_t response_length = 0;
        if (request.command == BGI_WINE_COMMAND_HELLO) {
            struct bgi_wine_hello_response response = {
                BGI_WINE_BRIDGE_VERSION,
                0,
                BGI_WINE_CAP_KEYBOARD | BGI_WINE_CAP_MOUSE
                    | BGI_WINE_CAP_RELATIVE_MOUSE | BGI_WINE_CAP_TEXT
                    | BGI_WINE_CAP_STATE_QUERY | BGI_WINE_CAP_TARGET_DISCOVERY,
                BGI_WINE_INPUT_MARKER
            };
            memcpy(response_payload, &response, sizeof(response));
            response_length = sizeof(response);
        } else if (request.command == BGI_WINE_COMMAND_AUTHENTICATE) {
            if (state->authenticated) {
                status = BGI_WINE_STATUS_ALREADY_AUTHENTICATED;
            } else if (!constant_time_equals(
                (const char *)payload, request.payload_length, state->token)) {
                status = BGI_WINE_STATUS_AUTHENTICATION_FAILED;
            } else {
                state->authenticated = true;
            }
        } else if (!state->authenticated) {
            status = BGI_WINE_STATUS_AUTHENTICATION_REQUIRED;
        } else {
            status = handle_authenticated_command(
                state, &request, payload, response_payload, &response_length);
        }

        if (!send_response(
            state->client, &request, status, response_payload, response_length)) {
            break;
        }
    }

    release_all(state);
    free(payload);
    free(response_payload);
    return true;
}

static bool parse_port(const char *text, uint16_t *port)
{
    char *end = NULL;
    unsigned long value = strtoul(text, &end, 10);
    if (end == text || *end != '\0' || value == 0 || value > 65535) return false;
    *port = (uint16_t)value;
    return true;
}

static int self_test(void)
{
    if (sizeof(struct bgi_wine_packet_header) != 24) return 1;
    if (sizeof(struct bgi_wine_target) != 80) return 2;
    if (sizeof(struct bgi_wine_key) != 8) return 3;
    if (sizeof(struct bgi_wine_mouse_button_payload) != 16) return 4;
    if (sizeof(struct bgi_wine_mouse_move) != 8) return 5;
    if (BGI_WINE_INPUT_MARKER != UINT64_C(0x42474957494E45)) return 6;
    puts("BetterGIWineInputBridge self-test passed");
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return self_test();
    if (argc != 3 || strcmp(argv[1], "--port") != 0) {
        fputs("usage: BetterGIWineInputBridge.exe --port <1-65535>\n", stderr);
        return 2;
    }

    uint16_t port;
    if (!parse_port(argv[2], &port)) {
        fputs("invalid port\n", stderr);
        return 2;
    }

    struct bridge_state state = {0};
    DWORD token_length = GetEnvironmentVariableA(
        "BETTERGI_WINE_BRIDGE_TOKEN", state.token, (DWORD)sizeof(state.token));
    if (token_length < 32 || token_length >= sizeof(state.token)) {
        fputs("BETTERGI_WINE_BRIDGE_TOKEN must contain 32-255 bytes\n", stderr);
        return 3;
    }

    WSADATA winsock;
    if (WSAStartup(MAKEWORD(2, 2), &winsock) != 0) return 4;

    SOCKET listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listener == INVALID_SOCKET) {
        WSACleanup();
        return 5;
    }

    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    InetPtonA(AF_INET, "127.0.0.1", &address.sin_addr);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) == SOCKET_ERROR
        || listen(listener, 1) == SOCKET_ERROR) {
        closesocket(listener);
        WSACleanup();
        return 6;
    }

    puts("BETTERGI_WINE_BRIDGE_READY");
    fflush(stdout);
    state.client = accept(listener, NULL, NULL);
    closesocket(listener);
    if (state.client == INVALID_SOCKET) {
        WSACleanup();
        return 7;
    }

    BOOL no_delay = TRUE;
    setsockopt(
        state.client, IPPROTO_TCP, TCP_NODELAY,
        (const char *)&no_delay, sizeof(no_delay));
    bool success = serve_client(&state);
    shutdown(state.client, SD_BOTH);
    closesocket(state.client);
    WSACleanup();
    SecureZeroMemory(state.token, sizeof(state.token));
    return success ? 0 : 8;
}
