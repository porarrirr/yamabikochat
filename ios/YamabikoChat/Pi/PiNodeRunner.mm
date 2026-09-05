#import "PiNodeRunner.h"
#import <NodeMobile/NodeMobile.h>
#import <UIKit/UIKit.h>
#import <unistd.h>
#import <fcntl.h>
#import <os/log.h>

@implementation PiNodeRunner

// Main-thread owned. Anonymous pipes survive iOS TCP socket reclamation.
static int PiLifecycleWriteFD = -1;
static NSFileHandle *PiLifecycleAcknowledgements;
static NSMutableData *PiLifecycleAckBuffer;
static NSMutableDictionary<NSString *, NSNumber *> *PiLifecycleBackgroundTasks;
static NSUInteger PiLifecycleGeneration = 0;

+ (void)finishLifecycleTask:(NSString *)generation {
    NSNumber *task = PiLifecycleBackgroundTasks[generation];
    if (!task) return;
    [PiLifecycleBackgroundTasks removeObjectForKey:generation];
    [UIApplication.sharedApplication endBackgroundTask:task.unsignedIntegerValue];
}

+ (void)sendLifecycleState:(NSString *)state {
    NSString *generation = [NSString stringWithFormat:@"%lu", (unsigned long)++PiLifecycleGeneration];
    if ([state isEqualToString:@"pause"]) {
        UIBackgroundTaskIdentifier task = [UIApplication.sharedApplication
            beginBackgroundTaskWithName:@"Pi listener suspension" expirationHandler:^{
                os_log_info(OS_LOG_DEFAULT, "Pi listener background execution allowance expired");
                if (PiLifecycleBackgroundTasks[generation] &&
                    UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
                    [self sendLifecycleState:@"suspend"];
                }
                [self finishLifecycleTask:generation];
            }];
        if (task != UIBackgroundTaskInvalid) PiLifecycleBackgroundTasks[generation] = @(task);
    }
    NSData *command = [[NSString stringWithFormat:@"%@:%@\n", state, generation]
        dataUsingEncoding:NSUTF8StringEncoding];
    ssize_t written;
    do { written = write(PiLifecycleWriteFD, command.bytes, command.length); }
    while (written < 0 && errno == EINTR);
    if (written != (ssize_t)command.length) {
        os_log_error(OS_LOG_DEFAULT, "Pi lifecycle pipe write failed: %{public}d", errno);
        [self finishLifecycleTask:generation];
    }
}

+ (void)installLifecycleWithWriteFD:(int)writeFD acknowledgementFD:(int)acknowledgementFD {
    PiLifecycleWriteFD = writeFD;
    PiLifecycleBackgroundTasks = [NSMutableDictionary dictionary];
    PiLifecycleAckBuffer = [NSMutableData data];
    PiLifecycleAcknowledgements = [[NSFileHandle alloc] initWithFileDescriptor:acknowledgementFD closeOnDealloc:NO];
    PiLifecycleAcknowledgements.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (!data.length) {
            handle.readabilityHandler = nil;
            os_log_error(OS_LOG_DEFAULT, "Pi lifecycle acknowledgement pipe closed");
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [PiLifecycleAckBuffer appendData:data];
            NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
            while (true) {
                NSRange range = [PiLifecycleAckBuffer rangeOfData:newline options:0
                    range:NSMakeRange(0, PiLifecycleAckBuffer.length)];
                if (range.location == NSNotFound) break;
                NSString *generation = [[NSString alloc] initWithData:
                    [PiLifecycleAckBuffer subdataWithRange:NSMakeRange(0, range.location)]
                    encoding:NSUTF8StringEncoding];
                [PiLifecycleAckBuffer replaceBytesInRange:NSMakeRange(0, range.location + 1)
                    withBytes:NULL length:0];
                if (generation) [self finishLifecycleTask:generation];
            }
        });
    };
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [self sendLifecycleState:@"pause"];
        }];
    [center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [self sendLifecycleState:@"resume"];
        }];
    [self sendLifecycleState:UIApplication.sharedApplication.applicationState == UIApplicationStateBackground
        ? @"pause" : @"resume"];
}

#if DEBUG
static NSString *PiNodeEngineState = @"notStarted";
static NSString *PiNodeEngineStartedAtMs = @"none";
static NSString *PiNodeEngineFinishedAtMs = @"none";
static NSString *PiNodeEngineExitCode = @"none";
static NSUInteger PiNodeEngineLaunchCount = 0;
#endif

+ (void)startEngineWithArguments:(NSArray<NSString *> *)arguments {
    int commands[2], acknowledgements[2];
    if (pipe(commands) != 0) {
        os_log_error(OS_LOG_DEFAULT, "Pi lifecycle command pipe creation failed: %{public}d", errno);
        return;
    }
    if (pipe(acknowledgements) != 0) {
        close(commands[0]); close(commands[1]);
        os_log_error(OS_LOG_DEFAULT, "Pi lifecycle acknowledgement pipe creation failed: %{public}d", errno);
        return;
    }
    // Never block the main thread, even if the Node event loop stops consuming.
    fcntl(commands[1], F_SETFL, O_NONBLOCK);
    fcntl(commands[1], F_SETNOSIGPIPE, 1);
    NSMutableArray<NSString *> *runtimeArguments = [arguments mutableCopy];
    if (runtimeArguments.count == 4) [runtimeArguments addObject:@""]; // Optional diagnostics path.
    [runtimeArguments addObject:[NSString stringWithFormat:@"%d", commands[0]]];
    [runtimeArguments addObject:[NSString stringWithFormat:@"%d", acknowledgements[1]]];
    arguments = runtimeArguments;
    int commandWriteFD = commands[1];
    int acknowledgementReadFD = acknowledgements[0];
    void (^installLifecycle)(void) = ^{
        [self installLifecycleWithWriteFD:commandWriteFD acknowledgementFD:acknowledgementReadFD];
    };
    if (NSThread.isMainThread) installLifecycle();
    else dispatch_sync(dispatch_get_main_queue(), installLifecycle);
#if DEBUG
    @synchronized(self) {
        PiNodeEngineState = @"starting";
        PiNodeEngineStartedAtMs = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970 * 1000.0];
        PiNodeEngineFinishedAtMs = @"none";
        PiNodeEngineExitCode = @"none";
        PiNodeEngineLaunchCount += 1;
    }
#endif
    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        size_t size = 0;
        for (NSString *argument in arguments) {
            size += strlen(argument.UTF8String) + 1;
        }

        char *buffer = (char *)calloc(size, sizeof(char));
        char **argv = (char **)calloc(arguments.count, sizeof(char *));
        char *position = buffer;
        for (NSUInteger index = 0; index < arguments.count; index++) {
            const char *value = arguments[index].UTF8String;
            const size_t length = strlen(value);
            memcpy(position, value, length);
            argv[index] = position;
            position += length + 1;
        }

#if DEBUG
        @synchronized(self) {
            PiNodeEngineState = @"executing";
        }
        int exitCode = node_start((int)arguments.count, argv);
        @synchronized(self) {
            PiNodeEngineState = @"exited";
            PiNodeEngineFinishedAtMs = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970 * 1000.0];
            PiNodeEngineExitCode = [NSString stringWithFormat:@"%d", exitCode];
        }
#else
        node_start((int)arguments.count, argv);
#endif
        free(argv);
        free(buffer);
    }];
    thread.name = @"Yamabiko Pi Agent";
    thread.stackSize = 2 * 1024 * 1024;
    [thread start];
}

#if DEBUG
+ (NSDictionary<NSString *, NSString *> *)engineDiagnostics {
    @synchronized(self) {
        return @{
            @"nativeEngineState": PiNodeEngineState,
            @"nativeEngineStartedAtMs": PiNodeEngineStartedAtMs,
            @"nativeEngineFinishedAtMs": PiNodeEngineFinishedAtMs,
            @"nativeEngineExitCode": PiNodeEngineExitCode,
            @"nativeEngineLaunchCount": [NSString stringWithFormat:@"%lu", (unsigned long)PiNodeEngineLaunchCount]
        };
    }
}
#endif

@end
