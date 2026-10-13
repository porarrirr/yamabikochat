#include "GenUICELBridge.h"
#include "quickjs/quickjs.h"
#include "GenUICELModules.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct { JSRuntime *runtime; JSContext *context; JSValue evaluate; struct timespec start; } CELContext;
static int interrupted(JSRuntime *runtime, void *opaque) {
    CELContext *cel = opaque; struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    double elapsed = (now.tv_sec-cel->start.tv_sec)+(now.tv_nsec-cel->start.tv_nsec)/1e9;
    return elapsed > .1;
}
static JSValue module_source(JSContext *context, JSValueConst this_value, int argc, JSValueConst *argv) {
    if (argc != 1) return JS_ThrowTypeError(context,"module name required");
    const char *name = JS_ToCString(context,argv[0]); if (!name) return JS_EXCEPTION;
    JSValue result = JS_UNDEFINED;
    for (size_t i=0;i<sizeof(cel_modules)/sizeof(cel_modules[0]);i++) {
        if (!strcmp(name,cel_modules[i].name)) {
            JSValue bytecode=JS_ReadObject(context,cel_modules[i].data,cel_modules[i].length,JS_READ_OBJ_BYTECODE);
            result=JS_IsException(bytecode)?bytecode:JS_EvalFunction(context,bytecode);break;
        }
    }
    JS_FreeCString(context,name);
    if(JS_IsUndefined(result))return JS_ThrowReferenceError(context,"unknown CEL module");
    return result;
}
void *GenUICELCreate(void) {
    CELContext *cel = calloc(1,sizeof(*cel)); if(!cel)return NULL;
    cel->runtime=JS_NewRuntime();if(!cel->runtime){free(cel);return NULL;}
    JS_SetMemoryLimit(cel->runtime,32*1024*1024);JS_SetMaxStackSize(cel->runtime,512*1024);
    cel->context=JS_NewContext(cel->runtime);if(!cel->context){JS_FreeRuntime(cel->runtime);free(cel);return NULL;}
    JSValue global=JS_GetGlobalObject(cel->context);
    JS_SetPropertyStr(cel->context,global,"moduleSource",JS_NewCFunction(cel->context,module_source,"moduleSource",1));
    JS_FreeValue(cel->context,global);
    const char *bootstrap=
        "(()=>{const cache=new Map();"
        "function require(name,from='cel/src/'){"
        "if(name.startsWith('.')){name=from+name;const parts=[];for(const part of name.split('/')){if(part==='..')parts.pop();else if(part!=='.')parts.push(part);}name=parts.join('/');}"
        "if(name==='valdi_core/src/JSX')return {jsx:{makeNodePrototype:()=>({})}};"
        "if(name==='dil_core/src/DILComponent')return {DILComponent:class{},DIL_COMPONENT_PROPERTIES:[]};"
        "if(name==='valdi_core/src/Style')return {Style:class{constructor(value){Object.assign(this,value)}}};"
        "if(name==='valdi_core/src/ElementRef')return {ElementRef:class{}};"
        "if(name==='valdi_core/src/Asset'||name==='coreutils/src/unicode/TextCoding')return {};"
        "if(name==='valdi_core/src/Device')return {Device:{isWeb:()=>false,isIOS:()=>true,isAndroid:()=>false,isDarkMode:()=>false,observeDarkMode:()=>({cancel(){}})}};"
        "if(name==='valdi_core/src/ModuleLoaderGlobal')return {getModuleLoader:()=>({onModuleRegistered:()=>({cancel(){}})})};"
        "if(cache.has(name))return cache.get(name).exports;"
        "const module={exports:{}};cache.set(name,module);"
        "moduleSource(name)(child=>require(child,name.slice(0,name.lastIndexOf('/')+1)),module,module.exports);return module.exports;}"
        "const {CELRuntime,CELExpressionResolver}=require('cel/src/CELRuntime');const {CELScopeImpl}=require('cel/src/CELScope');const runtime=new CELRuntime();const resolver=new CELExpressionResolver(runtime);"
        "return request=>{try{const input=JSON.parse(request);if(input.operation==='chart'){const svg=input.viewModel.chartType==='pie'?require('dil_charts/src/widgets/PieChart').renderPieChartSvg(input.viewModel,input.width,input.height):require('dil_charts/src/widgets/SvgChart').renderChartSvg(input.viewModel,input.width,input.height);return JSON.stringify({svg});}const compiled=resolver.getOrCompile(input.expression);"
        "const value=compiled(new CELScopeImpl(input.bindings || {}));return JSON.stringify({value:value===undefined?null:value});}"
        "catch(error){return JSON.stringify({error:String(error.message),kind:'CELExpressionError',stack:String(error.stack)});}};})()";
    cel->evaluate=JS_Eval(cel->context,bootstrap,strlen(bootstrap),"genui-cel",JS_EVAL_TYPE_GLOBAL);
    if(JS_IsException(cel->evaluate)){GenUICELDestroy(cel);return NULL;}
    JS_SetInterruptHandler(cel->runtime,interrupted,cel);return cel;
}
char *GenUICELCalculate(void *opaque, const char *request) {
    CELContext *cel=opaque;if(!cel || !request)return NULL;
    clock_gettime(CLOCK_MONOTONIC,&cel->start);
    JSValue argument=JS_NewString(cel->context,request);
    JSValue result=JS_Call(cel->context,cel->evaluate,JS_UNDEFINED,1,&argument);
    JS_FreeValue(cel->context,argument);
    if(JS_IsException(result)){JS_FreeValue(cel->context,JS_GetException(cel->context));return strdup("{\"error\":\"CEL evaluation budget exceeded\",\"kind\":\"CELExpressionError\"}");}
    const char *text=JS_ToCString(cel->context,result);char *copy=text?strdup(text):NULL;
    JS_FreeCString(cel->context,text);JS_FreeValue(cel->context,result);return copy;
}
void GenUICELFreeString(char *value){free(value);}
void GenUICELDestroy(void *opaque){CELContext *cel=opaque;if(!cel)return;JS_FreeValue(cel->context,cel->evaluate);JS_FreeContext(cel->context);JS_FreeRuntime(cel->runtime);free(cel);}
