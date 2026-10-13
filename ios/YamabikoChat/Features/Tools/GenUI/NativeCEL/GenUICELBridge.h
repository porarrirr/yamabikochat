#ifndef GENUI_CEL_BRIDGE_H
#define GENUI_CEL_BRIDGE_H
#ifdef __cplusplus
extern "C" {
#endif
void *GenUICELCreate(void);
char *GenUICELCalculate(void *context, const char *request);
void GenUICELFreeString(char *value);
void GenUICELDestroy(void *context);
#ifdef __cplusplus
}
#endif
#endif
