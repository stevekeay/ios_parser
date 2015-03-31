#include <ruby.h>

static VALUE rb_mIOSParser;
static VALUE rb_cCLexer;

typedef enum lex_token_state {
    LEX_STATE_ROOT,
    LEX_STATE_INTEGER,
    LEX_STATE_DECIMAL,
    LEX_STATE_WORD,
    LEX_STATE_COMMENT,
    LEX_STATE_BANNER,
    LEX_STATE_CERTIFICATE,
    LEX_STATE_INDENT,
} lex_token_state;

struct LexInfo {
    char *text;
    size_t pos;
    size_t token_start;
    size_t token_length;
    lex_token_state token_state;
    VALUE tokens;
    int indent;
    int indent_pos;
    int indents[100];
    char banner_delimiter;
};
typedef struct LexInfo LexInfo;

#define IS_SPACE(C)     C == ' ' || C == '\t' || C == '\r'
#define IS_NEWLINE(C)   C == '\n'
#define IS_COMMENT(C)   C == '#' || C == '!'
#define IS_DIGIT(C)     '0' <= C && C <= '9'
#define IS_DOT(C)       C == '.'
#define IS_DECIMAL(C)   IS_DIGIT(C) || IS_DOT(C)
#define IS_LETTER(C)    'a' <= C && C <= 'z' || 'A' <= C && C <= 'Z'
#define IS_PUNCT(C)     strchr("-+$:/,()|*#=<>!\"\\&@;%~{}'\"?[]_^", C)
#define IS_WORD(C)      IS_DECIMAL(C) || IS_LETTER(C) || IS_PUNCT(C)
#define IS_LEAD_ZERO(C) C != '0'

#define CURRENT_CHAR(LEX) LEX->text[LEX->pos]
#define TOKEN_EMPTY(LEX) LEX->token_length <= 0

#define MAKE_TOKEN(LEX, TOK) rb_ary_new3(2, rb_int_new(LEX->token_start), TOK)
#define ADD_TOKEN(LEX, TOK) rb_ary_push(LEX->tokens, MAKE_TOKEN(LEX, TOK))

#define CMD_LEN(CMD) (sizeof(CMD) - 1)
int is_certificate(LexInfo *lex) {
    VALUE indent_ary, indent, command_ary, command;
    int token_count, indent_pos, command_pos;

    token_count = RARRAY_LEN(lex->tokens);
    indent_pos = token_count - 6;
    if (indent_pos < 0) { return 0; }

    command_pos = token_count - 5;
    if (command_pos < 0) { return 0; }

    indent_ary = rb_ary_entry(lex->tokens, indent_pos);
    indent = rb_ary_entry(indent_ary, 1);
    if (TYPE(indent) != T_SYMBOL) { return 0; }
    if (rb_intern("INDENT") != SYM2ID(indent)) { return 0; }

    command_ary = rb_ary_entry(lex->tokens, command_pos);
    if (TYPE(command_ary) != T_ARRAY) { return 0; }
    if (RARRAY_LEN(command_ary) < 2) { return 0; }

    command = rb_ary_entry(command_ary, 1);
    if (TYPE(command) != T_STRING) { return 0; }

    StringValue(command);
    if (RSTRING_LEN(command) != CMD_LEN("certificate")) { return 0; }
    if (0 != strncmp(RSTRING_PTR(command), "certificate", 11)) { return 0; }

    return 1;
}

int is_banner(LexInfo *lex) {
    VALUE banner_ary, banner;
    int token_count = RARRAY_LEN(lex->tokens);
    int banner_pos = token_count - 2;

    if (banner_pos < 0) { return 0; }

    banner_ary = rb_ary_entry(lex->tokens, banner_pos);
    banner = rb_ary_entry(banner_ary, 1);
    if (TYPE(banner) != T_STRING) { return 0; }

    StringValue(banner);
    if (RSTRING_LEN(banner) != CMD_LEN("banner")) { return 0; }
    if (0 != strncmp(RSTRING_PTR(banner), "banner", 6)) { return 0; }

    return 1;
}

static void delimit(LexInfo *lex) {
    VALUE token;
    char string[lex->token_length + 1];

    if (TOKEN_EMPTY(lex)) {
        lex->token_state = LEX_STATE_ROOT;
        return;
    }

    switch (lex->token_state) {
    case (LEX_STATE_WORD):
    case (LEX_STATE_BANNER):
    case (LEX_STATE_CERTIFICATE):
        token = rb_str_new(&lex->text[lex->token_start], lex->token_length);
        break;

    case (LEX_STATE_INTEGER):
        strncpy(string, &lex->text[lex->token_start], lex->token_length);
        string[lex->token_length] = '\0';
        token = rb_int_new(atoi(string));
        break;

    case (LEX_STATE_DECIMAL):
        strncpy(string, &lex->text[lex->token_start], lex->token_length);
        string[lex->token_length] = '\0';
        token = rb_float_new(atof(string));
        break;

    case (LEX_STATE_COMMENT):
        lex->token_state = LEX_STATE_ROOT;
        return;

    default:
        rb_raise(rb_eRuntimeError,
                 "Unable to commit token %s at %d",
                 string, (int)lex->pos);
        return;
    }

    ADD_TOKEN(lex, token);
    lex->token_state = LEX_STATE_ROOT;
    lex->token_length = 0;
}

static void deallocate(void * lex) {
    xfree(lex);
}

static void mark(void *ptr) {
    LexInfo *lex = (LexInfo *)ptr;
    rb_gc_mark(lex->tokens);
}

static VALUE allocate(VALUE klass) {
    LexInfo * lex = ALLOC(LexInfo);
    return Data_Wrap_Struct(klass, mark, deallocate, lex);
}

static VALUE initialize(VALUE self, VALUE input_text) {
    LexInfo *lex;
    Data_Get_Struct(self, LexInfo, lex);

    lex->text = NULL;
    lex->pos = 0;
    lex->token_start = 0;
    lex->token_length = 0;
    lex->token_state = LEX_STATE_ROOT;
    lex->tokens = rb_ary_new();

    lex->indent = 0;
    lex->indent_pos = 0;
    lex->indents[0] = 0;

    return self;
}

static void process_root(LexInfo * lex);
static void process_start_of_line(LexInfo * lex);

static void process_newline(LexInfo *lex) {
    delimit(lex);
    lex->token_start = lex->pos;
    ADD_TOKEN(lex, ID2SYM(rb_intern("EOL")));
    lex->token_state = LEX_STATE_INDENT;
    lex->indent = 0;
}

static void process_space(LexInfo *lex) {
    delimit(lex);
}

static void process_comment(LexInfo *lex) {
    char c = CURRENT_CHAR(lex);

    if (IS_NEWLINE(c)) {
        lex->token_length = 0;
        delimit(lex);
    }
}

static void process_word(LexInfo *lex) {
    char c = CURRENT_CHAR(lex);

    if (IS_WORD(c)) {
        lex->token_length++;
    } else if (IS_SPACE(c)) {
        process_space(lex);
    } else if (IS_NEWLINE(c)) {
        process_newline(lex);
    }
}

static void process_decimal(LexInfo *lex) {
    char c = CURRENT_CHAR(lex);

    if (IS_DIGIT(c)) {
        lex->token_length++;
    } else if (IS_WORD(c)) {
        lex->token_length++;
        lex->token_state = LEX_STATE_WORD;
    } else if (IS_SPACE(c)) {
        process_space(lex);
    } else if (IS_NEWLINE(c)) {
        process_newline(lex);
    } else if (IS_WORD(c)) {
        process_word(lex);
    }
}

static void process_integer(LexInfo *lex) {
    char c = CURRENT_CHAR(lex);

    if (IS_DIGIT(c)) {
        lex->token_length++;
    } else if (c == '.') {
        lex->token_length++;
        lex->token_state = LEX_STATE_DECIMAL;
    } else if (IS_SPACE(c)) {
        process_space(lex);
    } else if (IS_NEWLINE(c)) {
        process_newline(lex);
    } else if (IS_WORD(c)) {
        process_word(lex);
    }
}

static void process_certificate(LexInfo *lex) {
    char quit[5];

    strncpy(quit, &CURRENT_CHAR(lex) - 5, 5);

    if (0 == strncmp("quit\n", quit, 5)) {
        int length = lex->token_length;
        VALUE token;

        length = length - 5;
        while(' ' == lex->text[lex->token_start + length - 1]) {
            length--;
        }
        lex->token_length = length;

        token = rb_str_new(&lex->text[lex->token_start], lex->token_length);

        rb_funcall(token, rb_intern("gsub!"), 2,
                   rb_str_new2("\n"), rb_str_new2(""));

        rb_funcall(token, rb_intern("gsub!"), 2,
                   rb_str_new2("  "), rb_str_new2(" "));

        ADD_TOKEN(lex, token);
        lex->token_length = 0;

        lex->token_start = lex->pos;
        ADD_TOKEN(lex, ID2SYM(rb_intern("CERTIFICATE_END")));

        process_newline(lex);
        process_start_of_line(lex);
    } else {
        lex->token_length++;
    }
}

static void start_certificate(LexInfo *lex) {
    lex->indent_pos--;
    rb_ary_pop(lex->tokens);
    rb_ary_pop(lex->tokens);
    ADD_TOKEN(lex, ID2SYM(rb_intern("CERTIFICATE_BEGIN")));
    process_certificate(lex);
}

static void process_banner(LexInfo *lex) {
    char c = CURRENT_CHAR(lex);

    if (c == lex->banner_delimiter) {
        lex->token_length++;
        delimit(lex);
        lex->token_start = lex->pos;
        ADD_TOKEN(lex, ID2SYM(rb_intern("BANNER_END")));
        if (lex->text[lex->pos + 1] == 'C') { lex->pos++; }
    } else {
        lex->token_length++;
    }
}

static void start_banner(LexInfo *lex) {
    lex->banner_delimiter = CURRENT_CHAR(lex);
    ADD_TOKEN(lex, ID2SYM(rb_intern("BANNER_BEGIN")));
}

static void process_start_of_line(LexInfo *lex) {
    char c = CURRENT_CHAR(lex);

    if (IS_SPACE(c)) {
        lex->indent++;
        return;
    }

    if (lex->indent > lex->indents[lex->indent_pos]) {
        lex->token_start = lex->pos;
        ADD_TOKEN(lex, ID2SYM(rb_intern("INDENT")));
        lex->indent_pos++;
        lex->indents[lex->indent_pos] = lex->indent;
    } else {
        while (lex->indent < lex->indents[lex->indent_pos]) {
            ADD_TOKEN(lex, ID2SYM(rb_intern("DEDENT")));
            lex->indent_pos--;
        }
    }

    process_root(lex);
}

static void process_root(LexInfo *lex) {
    char c;
    c = CURRENT_CHAR(lex);
    lex->token_start = lex->pos;

    if (IS_SPACE(c)) {
        delimit(lex);

    } else if (is_banner(lex)) {
        lex->token_state = LEX_STATE_BANNER;
        start_banner(lex);
        lex->pos = lex->pos + 2;
        lex->token_start = lex->pos;
        lex->token_length = 0;

    } else if (is_certificate(lex)) {
        lex->token_state = LEX_STATE_CERTIFICATE;
        start_certificate(lex);

    } else if (IS_NEWLINE(c)) {
        process_newline(lex);

    } else if (IS_COMMENT(c)) {
        lex->token_state = LEX_STATE_COMMENT;
        process_comment(lex);

    } else if (!(IS_LEAD_ZERO(c)) && IS_DIGIT(c)) {
        lex->token_state = LEX_STATE_INTEGER;
        process_integer(lex);

    } else if (IS_WORD(c)) {
        lex->token_state = LEX_STATE_WORD;
        process_word(lex);

    } else {
        rb_raise(rb_eTypeError,
                 "Attempted to lex unknown character %c at %d",
                 c, (int)lex->pos);
    }
}

static VALUE call(VALUE self, VALUE input_text) {
    LexInfo *lex;
    size_t input_len;

    if (TYPE(input_text) != T_STRING) {
        rb_raise(rb_eTypeError, "The argument to CLexer#call must be a String.");
        return Qnil;
    }

    Data_Get_Struct(self, LexInfo, lex);

    StringValue(input_text);
    lex->text = RSTRING_PTR(input_text);
    input_len = RSTRING_LEN(input_text);

    for (lex->pos = 0; lex->pos < input_len; lex->pos++) {
        switch(lex->token_state) {
        case (LEX_STATE_ROOT):
            process_root(lex);
            break;

        case (LEX_STATE_INDENT):
            process_start_of_line(lex);
            break;

        case (LEX_STATE_INTEGER):
            process_integer(lex);
            break;

        case (LEX_STATE_DECIMAL):
            process_decimal(lex);
            break;

        case (LEX_STATE_WORD):
            process_word(lex);
            break;

        case (LEX_STATE_COMMENT):
            process_comment(lex);
            break;

        case (LEX_STATE_BANNER):
            process_banner(lex);
            break;

        case (LEX_STATE_CERTIFICATE):
            process_certificate(lex);
            break;
        }
    }

    delimit(lex);
    lex->token_start = lex->pos;

    for (; lex->indent_pos > 0; lex->indent_pos--) {
        ADD_TOKEN(lex, ID2SYM(rb_intern("DEDENT")));
    }

    return lex->tokens;
}

void Init_c_lexer() {
    rb_mIOSParser = rb_define_module("IOSParser");
    rb_cCLexer = rb_define_class_under(rb_mIOSParser, "CLexer", rb_cObject);
    rb_define_alloc_func(rb_cCLexer, allocate);
    rb_define_method(rb_cCLexer, "initialize", initialize, 0);
    rb_define_method(rb_cCLexer, "call", call, 1);
}
