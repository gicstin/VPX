#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlobj.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <zlib.h>

#define TRAILER_MAGIC "VPXPACK1"
#define TRAILER_SIZE 64
#define ID_SIZE 40
#define APP_EXE L"VPX.exe"

typedef struct {
	char magic[8];
	uint64_t offset;
	uint64_t size;
	char id[ID_SIZE];
} Trailer;

static void fail(const wchar_t *message, DWORD code) {
	wchar_t text[1024];
	swprintf(text, 1024, L"%ls\n\nError code %lu", message, (unsigned long)code);
	MessageBoxW(NULL, text, L"VPX", MB_ICONERROR | MB_OK);
	ExitProcess(1);
}

static int read_at(HANDLE file, uint64_t offset, void *buffer, DWORD size) {
	LARGE_INTEGER position;
	position.QuadPart = (LONGLONG)offset;
	DWORD done = 0;
	return SetFilePointerEx(file, position, NULL, FILE_BEGIN) && ReadFile(file, buffer, size, &done, NULL) && done == size;
}

static int read_all(HANDLE file, void *buffer, uint64_t size) {
	uint8_t *cursor = (uint8_t *)buffer;
	while (size > 0) {
		DWORD chunk = size > 0x40000000 ? 0x40000000 : (DWORD)size;
		DWORD done = 0;
		if (!ReadFile(file, cursor, chunk, &done, NULL) || done != chunk) {
			return 0;
		}
		cursor += done;
		size -= done;
	}
	return 1;
}

static int write_all(HANDLE file, const void *buffer, uint64_t size) {
	const uint8_t *cursor = (const uint8_t *)buffer;
	while (size > 0) {
		DWORD chunk = size > 0x40000000 ? 0x40000000 : (DWORD)size;
		DWORD done = 0;
		if (!WriteFile(file, cursor, chunk, &done, NULL) || done != chunk) {
			return 0;
		}
		cursor += done;
		size -= done;
	}
	return 1;
}

static void make_parents(wchar_t *path) {
	for (wchar_t *cursor = path + 3; *cursor; cursor++) {
		if (*cursor == L'\\') {
			*cursor = 0;
			CreateDirectoryW(path, NULL);
			*cursor = L'\\';
		}
	}
}

static void remove_tree(const wchar_t *path) {
	wchar_t pattern[MAX_PATH * 2];
	swprintf(pattern, MAX_PATH * 2, L"%ls\\*", path);
	WIN32_FIND_DATAW entry;
	HANDLE find = FindFirstFileW(pattern, &entry);
	if (find != INVALID_HANDLE_VALUE) {
		do {
			if (wcscmp(entry.cFileName, L".") == 0 || wcscmp(entry.cFileName, L"..") == 0) {
				continue;
			}
			wchar_t child[MAX_PATH * 2];
			swprintf(child, MAX_PATH * 2, L"%ls\\%ls", path, entry.cFileName);
			if ((entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && !(entry.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
				remove_tree(child);
			} else {
				SetFileAttributesW(child, FILE_ATTRIBUTE_NORMAL);
				DeleteFileW(child);
			}
		} while (FindNextFileW(find, &entry));
		FindClose(find);
	}
	RemoveDirectoryW(path);
}

static void remove_old_versions(const wchar_t *root, const wchar_t *keep) {
	wchar_t pattern[MAX_PATH * 2];
	swprintf(pattern, MAX_PATH * 2, L"%ls\\*", root);
	WIN32_FIND_DATAW entry;
	HANDLE find = FindFirstFileW(pattern, &entry);
	if (find == INVALID_HANDLE_VALUE) {
		return;
	}
	do {
		if (!(entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || wcscmp(entry.cFileName, L".") == 0 || wcscmp(entry.cFileName, L"..") == 0 || wcscmp(entry.cFileName, keep) == 0) {
			continue;
		}
		wchar_t child[MAX_PATH * 2];
		swprintf(child, MAX_PATH * 2, L"%ls\\%ls", root, entry.cFileName);
		remove_tree(child);
	} while (FindNextFileW(find, &entry));
	FindClose(find);
}

static void extract(HANDLE self, const Trailer *trailer, const wchar_t *target) {
	LARGE_INTEGER position;
	position.QuadPart = (LONGLONG)trailer->offset;
	if (!SetFilePointerEx(self, position, NULL, FILE_BEGIN)) {
		fail(L"Cannot read the application payload.", GetLastError());
	}
	uint64_t remaining = trailer->size;
	for (;;) {
		uint16_t name_size = 0;
		if (!read_all(self, &name_size, sizeof(name_size))) {
			fail(L"The application payload is damaged.", 0);
		}
		if (name_size == 0) {
			break;
		}
		char name[1024];
		uint64_t sizes[2];
		if (name_size >= sizeof(name) || !read_all(self, name, name_size) || !read_all(self, sizes, sizeof(sizes))) {
			fail(L"The application payload is damaged.", 0);
		}
		name[name_size] = 0;
		if (sizes[1] > remaining) {
			fail(L"The application payload is damaged.", 0);
		}
		remaining -= sizes[1];
		uint8_t *packed = (uint8_t *)malloc(sizes[1] ? sizes[1] : 1);
		uint8_t *data = (uint8_t *)malloc(sizes[0] ? sizes[0] : 1);
		if (!packed || !data || !read_all(self, packed, sizes[1])) {
			fail(L"Not enough memory to unpack VPX.", 0);
		}
		uLongf unpacked = (uLongf)sizes[0];
		if (uncompress(data, &unpacked, packed, (uLong)sizes[1]) != Z_OK || unpacked != sizes[0]) {
			fail(L"The application payload is damaged.", 0);
		}
		wchar_t relative[1024];
		MultiByteToWideChar(CP_UTF8, 0, name, -1, relative, 1024);
		for (wchar_t *cursor = relative; *cursor; cursor++) {
			if (*cursor == L'/') {
				*cursor = L'\\';
			}
		}
		wchar_t path[MAX_PATH * 2];
		swprintf(path, MAX_PATH * 2, L"%ls\\%ls", target, relative);
		make_parents(path);
		HANDLE out = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
		if (out == INVALID_HANDLE_VALUE || !write_all(out, data, sizes[0])) {
			fail(L"Cannot write VPX files to the local app data folder.", GetLastError());
		}
		CloseHandle(out);
		free(packed);
		free(data);
	}
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR arguments, int show) {
	(void)instance;
	(void)previous;
	(void)arguments;
	(void)show;
	wchar_t self_path[MAX_PATH * 2];
	GetModuleFileNameW(NULL, self_path, MAX_PATH * 2);
	HANDLE self = CreateFileW(self_path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (self == INVALID_HANDLE_VALUE) {
		fail(L"Cannot open the VPX executable.", GetLastError());
	}
	LARGE_INTEGER self_size;
	GetFileSizeEx(self, &self_size);
	Trailer trailer;
	if (self_size.QuadPart < TRAILER_SIZE || !read_at(self, (uint64_t)self_size.QuadPart - TRAILER_SIZE, &trailer, sizeof(trailer)) || memcmp(trailer.magic, TRAILER_MAGIC, 8) != 0) {
		fail(L"This VPX executable has no application payload.", 0);
	}
	wchar_t id[ID_SIZE + 1];
	MultiByteToWideChar(CP_UTF8, 0, trailer.id, ID_SIZE, id, ID_SIZE);
	id[ID_SIZE] = 0;
	for (int i = ID_SIZE - 1; i >= 0 && (id[i] == 0 || id[i] == L' '); i--) {
		id[i] = 0;
	}

	wchar_t local[MAX_PATH];
	if (SHGetFolderPathW(NULL, CSIDL_LOCAL_APPDATA | CSIDL_FLAG_CREATE, NULL, 0, local) != S_OK) {
		fail(L"Cannot find the local app data folder.", GetLastError());
	}
	wchar_t root[MAX_PATH * 2];
	swprintf(root, MAX_PATH * 2, L"%ls\\VPX\\runtime\\", local);
	make_parents(root);
	root[wcslen(root) - 1] = 0;
	wchar_t target[MAX_PATH * 2];
	wchar_t ready[MAX_PATH * 2];
	swprintf(target, MAX_PATH * 2, L"%ls\\%ls", root, id);
	swprintf(ready, MAX_PATH * 2, L"%ls\\.ready", target);
	if (GetFileAttributesW(ready) == INVALID_FILE_ATTRIBUTES) {
		wchar_t staging[MAX_PATH * 2];
		swprintf(staging, MAX_PATH * 2, L"%ls.%lu.tmp", target, (unsigned long)GetCurrentProcessId());
		remove_tree(staging);
		CreateDirectoryW(staging, NULL);
		extract(self, &trailer, staging);
		wchar_t staging_ready[MAX_PATH * 2];
		swprintf(staging_ready, MAX_PATH * 2, L"%ls\\.ready", staging);
		HANDLE marker = CreateFileW(staging_ready, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
		if (marker != INVALID_HANDLE_VALUE) {
			CloseHandle(marker);
		}
		if (!MoveFileExW(staging, target, 0)) {
			remove_tree(target);
			if (!MoveFileExW(staging, target, 0)) {
				remove_tree(staging);
			}
		}
		if (GetFileAttributesW(ready) == INVALID_FILE_ATTRIBUTES) {
			fail(L"Cannot unpack VPX to the local app data folder.", GetLastError());
		}
	}
	CloseHandle(self);
	remove_old_versions(root, id);

	wchar_t app[MAX_PATH * 2];
	swprintf(app, MAX_PATH * 2, L"%ls\\%ls", target, APP_EXE);
	const wchar_t *rest = GetCommandLineW();
	if (*rest == L'"') {
		rest = wcschr(rest + 1, L'"');
		rest = rest ? rest + 1 : L"";
	} else {
		while (*rest && *rest != L' ' && *rest != L'\t') {
			rest++;
		}
	}
	size_t command_size = wcslen(app) + wcslen(rest) + 8;
	wchar_t *command = (wchar_t *)malloc(command_size * sizeof(wchar_t));
	swprintf(command, command_size, L"\"%ls\"%ls", app, rest);
	SetEnvironmentVariableW(L"VPX_LAUNCHER", self_path);

	STARTUPINFOW startup;
	PROCESS_INFORMATION process;
	ZeroMemory(&startup, sizeof(startup));
	startup.cb = sizeof(startup);
	ZeroMemory(&process, sizeof(process));
	if (!CreateProcessW(app, command, NULL, NULL, FALSE, 0, NULL, target, &startup, &process)) {
		fail(L"Cannot start VPX.", GetLastError());
	}
	CloseHandle(process.hThread);
	WaitForSingleObject(process.hProcess, INFINITE);
	DWORD exit_code = 0;
	GetExitCodeProcess(process.hProcess, &exit_code);
	CloseHandle(process.hProcess);
	return (int)exit_code;
}
