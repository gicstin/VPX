#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

static const wchar_t *skip_argument(const wchar_t *cursor) {
	while (*cursor == L' ' || *cursor == L'\t') {
		cursor++;
	}
	int quoted = 0;
	while (*cursor && (quoted || (*cursor != L' ' && *cursor != L'\t'))) {
		if (*cursor == L'\\') {
			const wchar_t *slashes = cursor;
			while (*cursor == L'\\') {
				cursor++;
			}
			if (*cursor == L'"' && ((cursor - slashes) % 2) == 1) {
				cursor++;
			}
			continue;
		}
		if (*cursor == L'"') {
			quoted = !quoted;
		}
		cursor++;
	}
	while (*cursor == L' ' || *cursor == L'\t') {
		cursor++;
	}
	return cursor;
}

static DWORD priority_class(int niceness) {
	if (niceness > 0) {
		return BELOW_NORMAL_PRIORITY_CLASS;
	}
	if (niceness < 0) {
		return ABOVE_NORMAL_PRIORITY_CLASS;
	}
	return NORMAL_PRIORITY_CLASS;
}

int wmain(int argc, wchar_t **argv) {
	int niceness = 10;
	int first = 1;
	if (argc > 2 && wcscmp(argv[1], L"-n") == 0) {
		niceness = _wtoi(argv[2]);
		first = 3;
	} else if (argc > 1 && wcsncmp(argv[1], L"-n", 2) == 0 && argv[1][2]) {
		niceness = _wtoi(argv[1] + 2);
		first = 2;
	}
	if (first >= argc) {
		return 125;
	}
	const wchar_t *command = GetCommandLineW();
	for (int i = 0; i < first; i++) {
		command = skip_argument(command);
	}
	SetPriorityClass(GetCurrentProcess(), priority_class(niceness));
	size_t size = wcslen(command) + 1;
	wchar_t *line = (wchar_t *)malloc(size * sizeof(wchar_t));
	wcscpy(line, command);
	STARTUPINFOW startup;
	PROCESS_INFORMATION process;
	ZeroMemory(&startup, sizeof(startup));
	startup.cb = sizeof(startup);
	startup.dwFlags = STARTF_USESTDHANDLES;
	startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
	startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
	startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
	ZeroMemory(&process, sizeof(process));
	HANDLE job = CreateJobObjectW(NULL, NULL);
	JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
	ZeroMemory(&limits, sizeof(limits));
	limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
	if (job) {
		SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits));
	}
	if (!CreateProcessW(NULL, line, NULL, NULL, TRUE, priority_class(niceness) | CREATE_SUSPENDED, NULL, NULL, &startup, &process)) {
		return 127;
	}
	if (job) {
		AssignProcessToJobObject(job, process.hProcess);
	}
	ResumeThread(process.hThread);
	CloseHandle(process.hThread);
	WaitForSingleObject(process.hProcess, INFINITE);
	DWORD exit_code = 0;
	GetExitCodeProcess(process.hProcess, &exit_code);
	CloseHandle(process.hProcess);
	return (int)exit_code;
}
