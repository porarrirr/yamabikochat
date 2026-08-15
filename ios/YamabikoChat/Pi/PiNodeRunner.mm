#import "PiNodeRunner.h"
#import <NodeMobile/NodeMobile.h>

@implementation PiNodeRunner

+ (void)startEngineWithArguments:(NSArray<NSString *> *)arguments {
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

        node_start((int)arguments.count, argv);
        free(argv);
        free(buffer);
    }];
    thread.name = @"Yamabiko Pi Agent";
    thread.stackSize = 2 * 1024 * 1024;
    [thread start];
}

@end
