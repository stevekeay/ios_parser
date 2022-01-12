#include <ruby.h>

static VALUE rb_mIOSParser;
static VALUE rb_cCLexer;
static VALUE rb_cToken;
VALUE rb_eLexError;

typedef enum lex_token_state {
    LEX_STATE_ROOT,
    LEX_STATE_INTEGER,
    LEX_STATE_DECIMAL,
    LEX_STATE_QUOTED_STRING,
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
    size_t line;
    size_t start_of_line;
    size_t token_line;
    lex_token_state token_state;
    VALUE tokens;
    int indent;
    int indent_pos;
    int indents[100];
    char banner_delimiter;
    char string_terminator;
};
typedef struct LexInfo LexInfo;

#define IS_SPACE(C)     C == ' ' || C == '\t' || C == '\r'
#define IS_NEWLINE(C)   C == '\n'
#define IS_COMMENT(C)   C == '!'
#define IS_DIGIT(C)     '0' <= C && C <= '9'
#define IS_DOT(C)       C == '.'
#define IS_DECIMAL(C)   IS_DIGIT(C) || IS_DOT(C)
#define IS_LETTER(C)    'a' <= C && C <= 'z' || 'A' <= C && C <= 'Z'
#define IS_PUNCT(C)     strchr("-+$:/,()|*#=<>!\"\\&@;%~{}'\"?[]_^`", C)
#define IS_WORD(C)      IS_DECIMAL(C) || IS_LETTER(C) || IS_PUNCT(C)
#define IS_LEAD_ZERO(C) C == '0'
#define IS_QUOTE(C)     C == '"' || C == '\''
#define IS_LEAD_COMMENT(C) C == '#' || C == '!'

#define CURRENT_CHAR(LEX) LEX->text[LEX->pos]
#define TOKEN_EMPTY(LEX) LEX->token_length <= 0
#define TOKEN_VALUE(TOK) RSTRUCT_GET(TOK, 0)

#define ADD_TOKEN(LEX, TOK) rb_ary_push(LEX->tokens, make_token(LEX, TOK))

#define CMD_LEN(CMD) (sizeof(CMD) - 1)

static VALUE make_token(LexInfo *lex, VALUE tok);

int is_certificate(LexInfo *lex) {
    VALUE indent_token, indent, command_token, command;
    int token_count, indent_pos, command_pos;

    token_count = RARRAY_LEN(lex->tokens);
    indent_pos = token_count - 6;
    if (indent_pos < 0) { return 0; }

    command_pos = token_count - 5;
    if (command_pos < 0) { return 0; }

    indent_token = rb_ary_entry(lex->tokens, indent_pos);
    indent = TOKEN_VALUE(indent_token);
    if (TYPE(indent) != T_SYMBOL) { return 0; }
    if (rb_intern("INDENT") != SYM2ID(indent)) { return 0; }

    command_token = rb_ary_entry(lex->tokens, command_pos);
    if (TYPE(command_token) != T_STRUCT) { return 0; }

    command = TOKEN_VALUE(command_token);
    if (TYPE(command) != T_STRING) { return 0; }

    StringValue(command);
    if (RSTRING_LEN(command) != CMD_LEN("certificate")) { return 0; }
    if (0 != strncmp(RSTRING_PTR(command), "certificate", 11)) { return 0; }

    return 1;
}

int is_authentication_banner_begin(LexInfo *lex) {
    VALUE authentication_ary, authentication, banner_ary, banner;
    int token_count = RARRAY_LEN(lex->tokens);
    int authentication_pos = token_count -2;
    int banner_pos = token_count - 1;

    if (banner_pos < 0) { return 0; }

    banner_ary = rb_ary_entry(lex->tokens, banner_pos);
    banner = TOKEN_VALUE(banner_ary);
    if (TYPE(banner) != T_STRING) { return 0; }

    StringValue(banner);
    if (RSTRING_LEN(banner) != CMD_LEN("banner")) { return 0; }
    if (0 != strncmp(RSTRING_PTR(banner), "banner", 6)) { return 0; }

    authentication_ary = rb_ary_entry(lex->tokens, authentication_pos);
    authentication = TOKEN_VALUE(authentication_ary);
    if (TYPE(authentication) != T_STRING) { return 0; }

    StringValue(authentication);
    if (RSTRING_LEN(authentication) != CMD_LEN("authentication")) { return 0; }
    if (0 != strncmp(RSTRING_PTR(authentication), "authentication", 14)) { return 0; }

    return 1;
}

int is_banner_begin(LexInfo *lex) {
    VALUE banner_ary, banner;
    int token_count = RARRAY_LEN(lex->tokens);
    int banner_pos = token_count - 2;

    if (banner_pos < 0) { return 0; }

    if (is_authentication_banner_begin(lex)) { return 1; }

    banner_ary = rb_ary_entry(lex->tokens, banner_pos);
    banner = TOKEN_VALUE(banner_ary);
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
    case (LEX_STATE_QUOTED_STRING):
    case (LEX_STATE_WORD):
    case (LEX_STATE_BANNER):
    case (LEX_STATE_CERTIFICATE):
        token = rb_str_new(&lex->text[lex->token_start], lex->token_length);
        break;

    case (LEX_STATE_INTEGER):
        strncpy(string, &lex->text[lex->token_start], lex->token_length);
        string[lex->token_length] = '\0';
        token = rb_int_new(atoll(string));
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

static VALUE make_token(LexInfo *lex, VALUE tok) {
    return rb_struct_new(rb_cToken,
                         tok,
                         rb_int_new(lex->token_start),
                         rb_int_new(lex->line),
                         rb_int_new(lex->token_start - lex->start_of_line + 1));
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
    lex->line = 1;
    lex->start_of_line = 0;
    lex->token_line = 0;
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
static void start_banner(LexInfo * lex);

static void find_start_of_line(LexInfo *lex, size_t from) {
    size_t pos = from;

    for (;;) {
        if (IS_NEWLINE(lex->text[pos])) {
            lex->start_of_line = pos + 1;
            return;
        } else if (pos <= 0) {
            lex->start_of_line = 0;
            return;
        } else {
            pos--;
        }
    }
}

static void process_newline(LexInfo *lex) {
    delimit(lex);

    if (is_banner_begin(lex)) {
      lex->token_state = LEX_STATE_BANNER;
      start_banner(lex);
      lex->pos = lex->pos + 1;
      lex->token_start = lex->pos;
      lex->token_length = 0;
      lex->token_line = 0;
      lex->line = lex->line + 1;
      return;
    }

    lex->token_start = lex->pos;
    ADD_TOKEN(lex, ID2SYM(rb_intern("EOL")));
    lex->token_state = LEX_STATE_INDENT;
    lex->indent = 0;
    lex->line = lex->line + 1;
}

static void process_space(LexInfo *lex) {
    delimit(lex);
}

static void process_comment(LexInfo *lex) {
    char c = CURRENT_CHAR(lex);
    int token_count = RARRAY_LEN(lex->tokens);
    VALUE last_token, last_value;

    if (0 < token_count) {
      last_token = rb_ary_entry(lex->tokens, token_count - 1);
      last_value = TOKEN_VALUE(last_token);

      if (TYPE(last_value) != T_SYMBOL) {
        ADD_TOKEN(lex, ID2SYM(rb_intern("EOL")));
      }
    }

    if (IS_NEWLINE(c)) {
        delimit(lex);
        lex->token_state = LEX_STATE_INDENT;
        lex->indent = 0;
        lex->line = lex->line + 1;
    }
}

static void process_quoted_string(LexInfo *lex) {
    char c = CURRENT_CHAR(lex);

    lex->token_length++;
    if (!lex->string_terminator) {
        lex->string_terminator = c;
    } else if (c == lex->string_terminator) {
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
        lex->token_state = LEX_STATE_WORD;
    }
}

static void process_certificate(LexInfo *lex) {
    char quit[6] = "quit\n";

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
        lex->line = lex->line + lex->token_line - 1;
        find_start_of_line(lex, lex->pos);
        ADD_TOKEN(lex, ID2SYM(rb_intern("CERTIFICATE_END")));

        find_start_of_line(lex, lex->pos - 2);
        lex->start_of_line++;
        lex->token_start = lex->pos;
        ADD_TOKEN(lex, ID2SYM(rb_intern("EOL")));

        lex->token_state = LEX_STATE_INDENT;
        lex->indent = 0;
        lex->line = lex->line + 1;

        process_start_of_line(lex);
    } else {
        if (IS_NEWLINE(CURRENT_CHAR(lex))) {
            lex->token_line++;
        }
        lex->token_length++;
    }
}

static void start_certificate(LexInfo *lex) {
    lex->indent_pos--;
    lex->token_line = 0;
    rb_ary_pop(lex->tokens);
    rb_ary_pop(lex->tokens);
    ADD_TOKEN(lex, ID2SYM(rb_intern("CERTIFICATE_BEGIN")));
    process_certificate(lex);
}

int is_banner_end_char(LexInfo *lex) {
    return CURRENT_CHAR(lex) == lex->banner_delimiter &&
        (0 < lex->pos && '\n' == lex->text[lex->pos - 1] ||
         '\n' == lex->text[lex->pos + 1]);
}

int is_banner_end_string(LexInfo *lex) {
    /* onlys accept the banner-ending string "EOF" */
    return (CURRENT_CHAR(lex) == 'F' &&
            lex->text[lex->pos - 1] == 'O' &&
            lex->text[lex->pos - 2] == 'E' &&
            lex->text[lex->pos - 3] == '\n');
}

static void process_banner(LexInfo *lex) {
    if (lex->banner_delimiter && is_banner_end_char(lex)) {
        lex->token_length++;
        delimit(lex);
        lex->token_start = lex->pos;
        lex->line = lex->line + lex->token_line;
        find_start_of_line(lex, lex->pos);
        ADD_TOKEN(lex, ID2SYM(rb_intern("BANNER_END")));
        if (lex->text[lex->pos + 1] == 'C') { lex->pos++; }
    } else if (!lex->banner_delimiter && is_banner_end_string(lex)) {
        lex->token_length -= 1;
        delimit(lex);
        lex->token_start = lex->pos;
        lex->line = lex->line + lex->token_line;
        find_start_of_line(lex, lex->pos);
        ADD_TOKEN(lex, ID2SYM(rb_intern("BANNER_END")));
    } else {
      if (IS_NEWLINE(lex->text[lex->pos + lex->token_length])) {
        lex->token_line++;
      }
      lex->token_length++;
    }
}

static void start_banner(LexInfo *lex) {
    char c = CURRENT_CHAR(lex);
    lex->banner_delimiter = (c == '\n') ? 0 : c;
    ADD_TOKEN(lex, ID2SYM(rb_intern("BANNER_BEGIN")));
    if ('\n' == lex->text[lex->pos + 1]) lex->line++;
    if ('\n' == lex->text[lex->pos + 2]) lex->pos++;
}

static void process_start_of_line(LexInfo *lex) {
    char c = CURRENT_CHAR(lex);

    if (lex->indent == 0) {
        lex->start_of_line = lex->pos;
    }

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
        while (lex->indent_pos >= 1 &&
               lex->indent <= lex->indents[lex->indent_pos-1]) {
            ADD_TOKEN(lex, ID2SYM(rb_intern("DEDENT")));
            lex->indent_pos--;
        }
    }

    if (IS_LEAD_COMMENT(c)) {
        lex->token_state = LEX_STATE_COMMENT;
    } else {
        process_root(lex);
    }
}

static void process_root(LexInfo *lex) {
    char c;
    c = CURRENT_CHAR(lex);
    lex->token_start = lex->pos;

    if (IS_SPACE(c)) {
        delimit(lex);

    } else if (is_banner_begin(lex)) {
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

    } else if (IS_QUOTE(c)) {
        lex->token_state = LEX_STATE_QUOTED_STRING;
        lex->string_terminator = '\0';
        process_quoted_string(lex);

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

        case (LEX_STATE_QUOTED_STRING):
            process_quoted_string(lex);
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

    if (lex->token_state == LEX_STATE_QUOTED_STRING) {
        rb_raise(rb_eLexError,
                 "Unterminated quoted string starting at %d: %.*s",
                 (int)lex->token_start,
                 (int)lex->token_length, &lex->text[lex->token_start]);
    }

    delimit(lex);
    lex->token_start = lex->pos - 1;
    lex->line = lex->line - 1;

    for (; lex->indent_pos > 0; lex->indent_pos--) {
        ADD_TOKEN(lex, ID2SYM(rb_intern("DEDENT")));
    }

    return lex->tokens;
}

void Init_c_lexer() {
    rb_mIOSParser = rb_define_module("IOSParser");
    rb_cCLexer = rb_define_class_under(rb_mIOSParser, "CLexer", rb_cObject);
    rb_eLexError = rb_define_class_under(rb_mIOSParser, "LexError",
                                         rb_eStandardError);
    rb_cToken = rb_path2class("IOSParser::Token");
    rb_define_alloc_func(rb_cCLexer, allocate);
    rb_define_method(rb_cCLexer, "initialize", initialize, 0);
    rb_define_method(rb_cCLexer, "call", call, 1);
}
