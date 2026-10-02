/* Focused harness for Plymouth's exported script engine (24.004.60).
 * Uses native PNG/font/image/math/sprite code; only display geometry and
 * daemon event registration are supplied by the harness. This is not KMS/boot QA.
 */
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
typedef struct { void *data, *global, *local, *self; } State;
typedef struct { int type; void *object; } Result;
static State *state;
static void *(*parse)(const char *, const char *);
static Result (*execute)(State *, void *);
static double (*number)(void *, const char *);
static char *(*string)(void *, const char *);
static void run(const char *source) {
    void *op = parse(source, "animation-audit"); assert(op);
    Result result = execute(state, op); assert(result.type != 2);
}
static void expect(const char *key, const char *value) {
    char *actual = string(state->global, key);
    assert(actual && strcmp(actual, value) == 0); free(actual);
}
#define SYMBOL(name) ({ void *sym = dlsym(lib, name); if (!sym) { fprintf(stderr,"Missing %s\n",name); exit(1); } sym; })
int main(int argc, char **argv) {
    assert(argc == 5);
    void *lib = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL); if (!lib) { puts(dlerror()); return 1; }
    State *(*new_state)(void *) = SYMBOL("script_state_new");
    void *(*list_new)(void) = SYMBOL("ply_list_new");
    void *(*images)(State *, const char *) = SYMBOL("script_lib_image_setup");
    void *(*sprites)(State *, void *) = SYMBOL("script_lib_sprite_setup");
    void *(*math)(State *) = SYMBOL("script_lib_math_setup");
    void *(*strings)(State *) = SYMBOL("script_lib_string_setup");
    void *(*file)(const char *) = SYMBOL("script_parse_file");
    parse = SYMBOL("script_parse_string"); execute = SYMBOL("script_execute");
    number = SYMBOL("script_obj_hash_get_number"); string = SYMBOL("script_obj_hash_get_string");
    state = new_state(NULL); images(state, argv[2]); sprites(state, list_new()); math(state); strings(state);
    char prelude[3000];
    snprintf(prelude, sizeof prelude,
      "fun w(){return %s;} fun h(){return %s;} fun x(){return 37;} fun y(){return 19;} "
      "Window.GetWidth=w;Window.GetHeight=h;Window.GetX=x;Window.GetY=y;"
      "fun register(callback){} Plymouth.SetRefreshFunction=register;Plymouth.SetRefreshRate=register;"
      "Plymouth.SetDisplayPasswordFunction=register;Plymouth.SetDisplayQuestionFunction=register;"
      "Plymouth.SetDisplayNormalFunction=register;Plymouth.SetDisplayMessageFunction=register;Plymouth.SetHideMessageFunction=register;Plymouth.SetDisplayHotplugFunction=register;",
      argv[3], argv[4]); run(prelude);
    char path[4096]; snprintf(path,sizeof path,"%s/crimson-apollo.script",argv[2]);
    void *op = file(path); assert(op); assert(execute(state,op).type != 2);
    run("font_test=Image.Text(\"Boot details\",1,1,1).GetWidth();");
    assert(isfinite(number(state->global,"font_test")) && number(state->global,"font_test") > 0);
    for (int i=0;i<288;i++) {
      run("refresh_callback(); test_x=ship.GetX();test_y=ship.GetY();test_w=base_ship.GetWidth();test_h=base_ship.GetHeight();");
      assert(number(state->global,"test_x") >= 37); assert(number(state->global,"test_y") >= 19);
      assert(number(state->global,"test_x")+number(state->global,"test_w") <= 37+atoi(argv[3]));
      assert(number(state->global,"test_y")+number(state->global,"test_h") <= 19+atoi(argv[4]));
    }
    run("display_password_callback(\"Unlock disk\",100000); message_callback(\"A status message\");"); expect("status","password"); expect("active_answer","********************************");
    run("hide_message_callback(\"A different message\");"); expect("status","password");
    run("hide_message_callback(\"A status message\"); display_normal_callback();"); expect("status","normal");
    run("display_question_callback(\"Select a recovery option\",\"recovery\");"); expect("status","question");
    run("display_normal_callback(); message_callback(\"An unusually long boot error with enough words to exercise wrapping across the available display width without hiding a password prompt or overlapping the artwork\");"); expect("status","message");
    run("hide_message_callback(\"other\");"); expect("status","message");
    run("hide_message_callback(message); refresh_callback();"); expect("status","normal");
    run("fun small_w(){return 640;} fun small_h(){return 480;} Window.GetWidth=small_w;Window.GetHeight=small_h;hotplug_callback();refresh_callback();display_password_callback(\"Unlock again\",3);hotplug_callback();"); expect("status","password");
    printf("Native Plymouth script/image/sprite audit passed: %sx%s, offset 37,19\n",argv[3],argv[4]);
    return 0;
}
