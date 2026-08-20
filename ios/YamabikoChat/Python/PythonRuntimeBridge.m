#import "PythonRuntimeBridge.h"

#import <Python/Python.h>
#import <dispatch/dispatch.h>
#import <mach/mach.h>

@interface YBPythonWorkItem : NSObject
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, copy) NSString *code;
@property(nonatomic, copy) NSString *optionsJSON;
@property(nonatomic, copy) void (^completion)(NSString *);
@end

@implementation YBPythonWorkItem
@end

@interface PythonRuntimeBridge ()
@property(nonatomic, copy) NSString *pythonHome;
@property(nonatomic, copy) NSString *harnessPath;
@property(nonatomic, copy, nullable) NSString *sitePackagesPath;
@property(nonatomic, strong) NSThread *pythonThread;
@property(nonatomic, strong) NSCondition *startupCondition;
@property(nonatomic, copy, nullable) NSString *startupError;
@property(nonatomic) BOOL startupFinished;
@property(nonatomic) unsigned long pythonThreadID;
@property(nonatomic) PyThreadState *savedThreadState;
@end

@implementation PythonRuntimeBridge

- (instancetype)initWithPythonHome:(NSString *)pythonHome
                        harnessPath:(NSString *)harnessPath
                   sitePackagesPath:(nullable NSString *)sitePackagesPath {
    self = [super init];
    if (self) {
        _pythonHome = [pythonHome copy];
        _harnessPath = [harnessPath copy];
        _sitePackagesPath = [sitePackagesPath copy];
        _startupCondition = [[NSCondition alloc] init];
        _pythonThread = [[NSThread alloc] initWithTarget:self selector:@selector(pythonThreadMain) object:nil];
        _pythonThread.name = @"com.porarri.yamabikochat.python";
        _pythonThread.qualityOfService = NSQualityOfServiceUserInitiated;
        [_pythonThread start];
        [_startupCondition lock];
        while (!_startupFinished) {
            [_startupCondition wait];
        }
        [_startupCondition unlock];
    }
    return self;
}

- (void)pythonThreadMain {
    @autoreleasepool {
        NSString *error = [self initializePython];
        [self.startupCondition lock];
        self.startupError = error;
        self.startupFinished = YES;
        [self.startupCondition signal];
        [self.startupCondition unlock];

        if (error != nil) {
            return;
        }
        NSPort *keepAlive = [NSMachPort port];
        [[NSRunLoop currentRunLoop] addPort:keepAlive forMode:NSDefaultRunLoopMode];
        while (!self.pythonThread.cancelled) {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
            }
        }
    }
}

- (nullable NSString *)initializePython {
    PyStatus status;
    PyPreConfig preconfig;
    PyPreConfig_InitIsolatedConfig(&preconfig);
    preconfig.utf8_mode = 1;
    status = Py_PreInitialize(&preconfig);
    if (PyStatus_Exception(status)) {
        return [self messageForStatus:status];
    }

    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.buffered_stdio = 0;
    config.write_bytecode = 0;
    config.install_signal_handlers = 0;
    config.module_search_paths_set = 1;

    status = PyConfig_SetBytesString(&config, &config.program_name, "YamabikoChat");
    if (!PyStatus_Exception(status)) {
        status = PyConfig_SetBytesString(&config, &config.home, self.pythonHome.fileSystemRepresentation);
    }
    if (!PyStatus_Exception(status)) {
        NSString *stdlib = [self.pythonHome stringByAppendingPathComponent:@"lib/python3.14"];
        NSString *dynload = [stdlib stringByAppendingPathComponent:@"lib-dynload"];
        status = [self appendPath:stdlib toList:&config.module_search_paths];
        if (!PyStatus_Exception(status)) {
            status = [self appendPath:dynload toList:&config.module_search_paths];
        }
        if (!PyStatus_Exception(status) && self.sitePackagesPath.length > 0) {
            status = [self appendPath:self.sitePackagesPath toList:&config.module_search_paths];
        }
        if (!PyStatus_Exception(status)) {
            status = [self appendPath:self.harnessPath.stringByDeletingLastPathComponent
                               toList:&config.module_search_paths];
        }
    }
    if (!PyStatus_Exception(status)) {
        status = Py_InitializeFromConfig(&config);
    }
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        return [self messageForStatus:status];
    }

    self.pythonThreadID = PyThread_get_thread_ident();
    PyObject *module = PyImport_ImportModule("yamabiko_runtime");
    if (module == NULL) {
        return [self fetchPythonError];
    }
    Py_DECREF(module);
    self.savedThreadState = PyEval_SaveThread();
    return nil;
}

- (PyStatus)appendPath:(NSString *)path toList:(PyWideStringList *)list {
    wchar_t *decoded = Py_DecodeLocale(path.fileSystemRepresentation, NULL);
    if (decoded == NULL) {
        return PyStatus_Error("Unable to decode Python module path");
    }
    PyStatus status = PyWideStringList_Append(list, decoded);
    PyMem_RawFree(decoded);
    return status;
}

- (NSString *)messageForStatus:(PyStatus)status {
    if (status.err_msg != NULL) {
        return [NSString stringWithUTF8String:status.err_msg];
    }
    return @"CPython initialization failed";
}

- (void)executeSession:(NSString *)sessionID
                   code:(NSString *)code
            optionsJSON:(NSString *)optionsJSON
             completion:(void (^)(NSString *))completion {
    if (self.startupError != nil) {
        completion([self errorJSONWithType:@"PythonInitializationError" message:self.startupError]);
        return;
    }
    YBPythonWorkItem *item = [[YBPythonWorkItem alloc] init];
    item.sessionID = sessionID;
    item.code = code;
    item.optionsJSON = optionsJSON;
    item.completion = completion;
    [self performSelector:@selector(executeWorkItem:) onThread:self.pythonThread withObject:item waitUntilDone:NO];
}

- (void)executeWorkItem:(YBPythonWorkItem *)item {
    PyEval_RestoreThread(self.savedThreadState);
    self.savedThreadState = NULL;
    NSString *result = nil;
    PyObject *module = PyImport_ImportModule("yamabiko_runtime");
    PyObject *function = module == NULL ? NULL : PyObject_GetAttrString(module, "run_cell");
    if (function != NULL && PyCallable_Check(function)) {
        PyObject *args = Py_BuildValue("(sss)", item.sessionID.UTF8String, item.code.UTF8String, item.optionsJSON.UTF8String);
        PyObject *value = PyObject_CallObject(function, args);
        Py_DECREF(args);
        if (value != NULL) {
            const char *utf8 = PyUnicode_AsUTF8(value);
            if (utf8 != NULL) {
                result = [NSString stringWithUTF8String:utf8];
            }
            Py_DECREF(value);
        }
    }
    if (result == nil) {
        result = [self errorJSONWithType:@"PythonBridgeError" message:[self fetchPythonError]];
    }
    Py_XDECREF(function);
    Py_XDECREF(module);
    self.savedThreadState = PyEval_SaveThread();
    item.completion(result);
}

- (void)requestInterruptWithExceptionName:(NSString *)exceptionName {
    if (self.pythonThreadID == 0) {
        return;
    }
    unsigned long targetThreadID = self.pythonThreadID;
    BOOL useMemoryError = [exceptionName isEqualToString:@"MemoryError"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // An attached thread state and the GIL are required around the C API.
        // If a native extension never releases the GIL this block may wait, but
        // the Swift watchdog remains independent and poisons the interpreter.
        PyGILState_STATE gilState = PyGILState_Ensure();
        PyObject *exception = useMemoryError ? PyExc_MemoryError : PyExc_TimeoutError;
        int affected = PyThreadState_SetAsyncExc(targetThreadID, exception);
        if (affected > 1) {
            PyThreadState_SetAsyncExc(targetThreadID, NULL);
        }
        PyGILState_Release(gilState);
    });
}

- (uint64_t)physicalFootprintBytes {
    task_vm_info_data_t info = {0};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
    return result == KERN_SUCCESS ? info.phys_footprint : 0;
}

- (NSString *)fetchPythonError {
    if (!PyErr_Occurred()) {
        return @"Embedded Python returned no result";
    }
    PyObject *type = NULL;
    PyObject *value = NULL;
    PyObject *traceback = NULL;
    PyErr_Fetch(&type, &value, &traceback);
    PyErr_NormalizeException(&type, &value, &traceback);
    PyObject *text = value == NULL ? NULL : PyObject_Str(value);
    const char *utf8 = text == NULL ? NULL : PyUnicode_AsUTF8(text);
    NSString *message = utf8 == NULL ? @"Unknown Python error" : [NSString stringWithUTF8String:utf8];
    Py_XDECREF(text);
    Py_XDECREF(type);
    Py_XDECREF(value);
    Py_XDECREF(traceback);
    return message;
}

- (NSString *)errorJSONWithType:(NSString *)type message:(NSString *)message {
    NSDictionary *object = @{
        @"status": @"error",
        @"stdout": @"",
        @"stderr": @"",
        @"result_repr": [NSNull null],
        @"artifacts": @[],
        @"duration_ms": @0,
        @"error": @{@"type": type, @"message": message, @"traceback": @""}
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
