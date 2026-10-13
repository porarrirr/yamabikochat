#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "quickjs/quickjs.h"
int main(int argc, char **argv) {
 FILE *f=fopen(argv[1],"rb"); if(!f)return 2;
 fseek(f,0,SEEK_END); size_t n=ftell(f); rewind(f);
 unsigned char *data=malloc(n); fread(data,1,n,f); fclose(f);
 JSRuntime *rt=JS_NewRuntime(); JSContext *ctx=JS_NewContext(rt);
 JSValue v=JS_ReadObject(ctx,data+4,n-4,JS_READ_OBJ_BYTECODE);
 if(JS_IsException(v)){ JSValue e=JS_GetException(ctx); const char *s=JS_ToCString(ctx,e);fprintf(stderr,"%s\n",s);return 1; }
 if(argc>2){
 JSValue fn=JS_EvalFunction(ctx,v); JSValue ex=JS_NewObject(ctx); JSValue mo=JS_NewObject(ctx);
 const char *reqSource="(name) => ({Device:{isWeb:()=>false,isAndroid:()=>false},DILDynamicTextStyle:new Proxy({}, {get:(_,key)=>key}),systemFont:(...args)=>args.join(' '),resolveDILDynamicFont:(...args)=>args[0],dynamicFont:(...args)=>args[0]})";
 JSValue req=JS_Eval(ctx,reqSource,strlen(reqSource),"platform",JS_EVAL_TYPE_GLOBAL);
 JSValue args[]={req,mo,ex}; JSValue result=JS_Call(ctx,fn,JS_UNDEFINED,3,args);
 if(JS_IsException(result)){JSValue e=JS_GetException(ctx); const char *str=JS_ToCString(ctx,e);fprintf(stderr,"%s\n",str);return 1;}
 JSValue source=JS_GetPropertyStr(ctx,ex,"componentSource");
 if(JS_IsString(source)){const char *str=JS_ToCString(ctx,source);puts("SOURCE_START");puts(str);puts("SOURCE_END");JS_FreeCString(ctx,str);}
 JS_SetPropertyStr(ctx,JS_GetGlobalObject(ctx),"exports",JS_DupValue(ctx,ex));
 const char *script=argv[2]; result=JS_Eval(ctx,script,strlen(script),"extract",JS_EVAL_TYPE_GLOBAL);
 const char *str=JS_ToCString(ctx,result);puts(str);JS_FreeCString(ctx,str);
 return 0;
 }
 JS_FreeValue(ctx,v); JS_FreeContext(ctx); JS_FreeRuntime(rt);free(data);return 0;
}