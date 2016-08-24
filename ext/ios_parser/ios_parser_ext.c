#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#include <stdio.h>

#define MAX_INDENT_LEVELS 100

#define CURRENT(LEX) LEX->text[LEX->pos]

#define IS_COMMENT(C) (C == '!')
#define IS_DECIMAL(C) (IS_DIGIT(C) || IS_DOT(C))
#define IS_DIGIT(C)   ('0' <= C && C <= '9')
#define IS_DOT(C)     (C == '.')
#define IS_LETTER(C)  ('a' <= C && C <= 'z' || 'A' <= C && C <= 'Z')
#define IS_NEWLINE(C) (C == '\n')
#define IS_PUNCT(C)   (strchr("-+$:/,()|*#=<>!\"\\&@;%~{}'\"?[]_^`", C))
#define IS_QUOTE(C)   (C == '"' || C == '\'')
#define IS_SPACE(C)   (C == ' ' || C == '\t' || C == '\r')
#define IS_BLANK(C)   (IS_NEWLINE(C) || IS_SPACE(C))
#define IS_WORD(C)    (IS_DECIMAL(C) || IS_LETTER(C) || IS_PUNCT(C))
#define IS_ZERO(C)    (C == '0')
#define IS_LEAD_COMMENT(C) (C == '!' || C == '#')

#define ON_COMMENT(LEX) IS_COMMENT(CURRENT(LEX))
#define ON_DECIMAL(LEX) IS_DECIMAL(CURRENT(LEX))
#define ON_DIGIT(LEX)   IS_DIGIT(CURRENT(LEX))
#define ON_DOT(LEX)     IS_DOT(CURRENT(LEX))
#define ON_LETTER(LEX)  IS_LETTER(CURRENT(LEX))
#define ON_NEWLINE(LEX) IS_NEWLINE(CURRENT(LEX))
#define ON_PUNCT(LEX)   IS_PUNCT(CURRENT(LEX))
#define ON_QUOTE(LEX)   IS_QUOTE(CURRENT(LEX))
#define ON_SPACE(LEX)   IS_SPACE(CURRENT(LEX))
#define ON_WORD(LEX)    IS_WORD(CURRENT(LEX))
#define ON_ZERO(LEX)    IS_ZERO(CURRENT(LEX))
#define ON_LEAD_COMMENT(LEX) IS_LEAD_COMMENT(CURRENT(LEX))

typedef enum TokenType {
  TOKEN_ERROR,
  TOKEN_STRING,
  TOKEN_INTEGER,
  TOKEN_DECIMAL,
  TOKEN_COMMENT,
  TOKEN_INDENT,
  TOKEN_DEDENT,
  TOKEN_EOL,
  TOKEN_BANNER_BEGIN,
  TOKEN_BANNER_END,
  TOKEN_CERTIFICATE_BEGIN,
  TOKEN_CERTIFICATE_END
} TokenType;

typedef struct Token {
  char* value;
  int   pos;                  /* original starting offset within text */
  TokenType type;
} Token;

typedef struct TokenStream {
  int size;                   /* number of tokens stored */
  int capacity;               /* physical size of token array */
  Token* tokens;              /* dynamic array to store tokens */
} TokenStream;

typedef struct Lexer {
  char* text;                 /* the string to lex */
  int   size;                 /* size of text in characters */
  int   pos;                  /* current offset within text */
  int   token_start;          /* starting offset of current token within text */
  int   token_size;           /* size in characters of current token */
  int   indent_columns;       /* size in characters of the current indentation level */
  int   indent_levels;        /* current number of indentation levels */
  int   indents[MAX_INDENT_LEVELS]; /* size in characters of each indentation level */
  TokenStream* ts;            /* collected tokens */
  TokenType    token_type;    /* type of the current token */
} Lexer;

bool on_banner(Lexer* lex) {
  char* command = NULL;

  if (3 <= lex->ts->size && lex->ts->tokens[lex->ts->size - 3].value) {
    command = lex->ts->tokens[lex->ts->size - 3].value;
    return 0 == strcmp("banner", command);
  }

  return false;
}

int on_certificate(Lexer* lex) {
  TokenType indent_type;
  char* command = NULL;

  if (6 <= lex->ts->size && lex->ts->tokens[lex->ts->size - 5].value) {
    indent_type = lex->ts->tokens[lex->ts->size - 6].type;
    if (indent_type != TOKEN_INDENT) return false;

    command = lex->ts->tokens[lex->ts->size - 5].value;
    return 0 == strcmp("certificate", command);
  }
  return false;
}

void error_token(Lexer *lex, char* format) {
  Token* token;
  char* value = malloc(sizeof(char) * 50);
  char message[21];

  strncpy(message, &lex->text[lex->token_start], 20);
  message[21] = '\0';

  snprintf(value, 50, format, lex->token_start, message);
  token = &lex->ts->tokens[lex->ts->size];
  token->type = TOKEN_ERROR;
  token->value = value;
  lex->ts->size++;
}

Token* finish_token(Lexer* lex, TokenType type, bool has_value) {
  Token* token;
  char* value = NULL;

  if (has_value) {
    value = malloc((lex->token_size + 1) * sizeof(char));
    value[lex->token_size] = '\0';
    strncpy(value, &lex->text[lex->token_start], lex->token_size);
  }

  if (lex->ts->capacity <= lex->ts->size) {
    lex->ts->capacity = lex->ts->capacity * 2;
    lex->ts->tokens = realloc(lex->ts->tokens, lex->ts->capacity * sizeof(Token));
  }

  token = &lex->ts->tokens[lex->ts->size];
  token->type = type;
  token->pos = lex->token_start;
  token->value = value;
  lex->ts->size++;
  return token;
}

void lex_string(Lexer* lex) {
  char delimiter = '\0';

  if (CURRENT(lex) == '\'' || CURRENT(lex) == '"') {
    delimiter = CURRENT(lex);
    lex->pos++;
  }

  for (; lex->pos < lex->size; lex->pos++) {
    if (delimiter && CURRENT(lex) == delimiter) {
      lex->token_size = lex->pos - lex->token_start + 1;
      finish_token(lex, TOKEN_STRING, true);
      return;
    } else if (!delimiter && (ON_NEWLINE(lex) || ON_SPACE(lex))) {
      lex->token_size = lex->pos - lex->token_start;
      finish_token(lex, TOKEN_STRING, true);
      lex->pos--;
      return;
    }
  }

  if (delimiter) {
    error_token(lex, "Unterminated quoted string starting at %d: %s");
  } else {
    lex->token_size = lex->pos - lex->token_start;
    finish_token(lex, TOKEN_STRING, true);
  }
}

void lex_decimal(Lexer* lex) {
  for (; lex->pos < lex->size; lex->pos++) {
    if (ON_DIGIT(lex)) {
      /* continue */
    } else if (ON_WORD(lex)) {
      lex_string(lex);
      return;
    } else {
      lex->token_size = lex->pos - lex->token_start;
      finish_token(lex, TOKEN_DECIMAL, true);
      lex->pos--;
      return;
    }
  }

  lex->token_size = lex->pos - lex->token_start;
  finish_token(lex, TOKEN_DECIMAL, true);
}

void lex_integer(Lexer* lex) {
  for (; lex->pos < lex->size; lex->pos++) {
    if (ON_DIGIT(lex)) {
      /* continue */
    } else if (ON_DOT(lex)) {
      lex->pos++;
      lex_decimal(lex);
      return;
    } else if (ON_NEWLINE(lex) || ON_SPACE(lex)) {
      lex->token_size = lex->pos - lex->token_start;
      finish_token(lex, TOKEN_INTEGER, true);
      lex->pos--;
      return;
    } else {
      lex->pos++;
      lex_string(lex);
      return;
    }
  }

  lex->token_size = lex->pos - lex->token_start;
  finish_token(lex, TOKEN_INTEGER, true);
}

bool lex_indent_update(Lexer* lex, int columns) {
  if (columns < lex->indent_columns) {
    while (lex->indent_levels && columns <= lex->indents[lex->indent_levels - 1]) {
      lex->indent_levels--;
      lex->indent_columns = lex->indents[lex->indent_levels];
      finish_token(lex, TOKEN_DEDENT, false);
    }
  } else if (MAX_INDENT_LEVELS <= lex->indent_columns + 1) {
    error_token(lex, "Too many levels of indentation at %d near %s");
    return false;
  } else if (lex->indent_columns < columns) {
    lex->token_start = lex->pos;
    lex->indent_columns = columns;
    lex->indent_levels++;
    lex->indents[lex->indent_levels] = columns;
    finish_token(lex, TOKEN_INDENT, false);
  }
  return true;
}

void lex_comment(Lexer* lex) {
  for (; lex->pos < lex->size; lex->pos++) {
    if (ON_NEWLINE(lex)) {
      return;
    } else {
      /* continue */
    }
  }
}

void lex_banner(Lexer* lex) {
  Token* delimiter_token;
  char* delimiter_string;
  char delimiter;

  delimiter_token = &lex->ts->tokens[lex->ts->size - 1];
  delimiter_string = delimiter_token->value;
  delimiter = delimiter_string[0];
  free(delimiter_token->value);
  delimiter_token->value = NULL;
  delimiter_token->type = TOKEN_BANNER_BEGIN;

  lex->pos++;
  while (ON_SPACE(lex)) lex->pos++;
  lex->token_start = lex->pos;

  for (; lex->pos < lex->size; lex->pos++) {
    if (CURRENT(lex) == delimiter &&
        (lex->text[lex->pos - 1] == '\n' ||
         lex->pos < lex->size && lex->text[lex->pos + 1] == '\n')) {
      lex->token_size = lex->pos - lex->token_start;
      finish_token(lex, TOKEN_STRING, true);
      lex->token_start = lex->pos;
      finish_token(lex, TOKEN_BANNER_END, false);
      while (!ON_SPACE(lex) && lex->pos < lex->size) lex->pos++;
      lex->pos -= 2;
      lex->token_start = lex->pos;
      return;
    }
  }
}

void compact_spaces(char* text) {
  int size, i;
  int pos = 0;
  if (!text) return;
  size = strlen(text);

  for (i = 0; i <= size; i++) {
    if (IS_BLANK(text[i])) {
      text[pos++] = ' ';
      for (; i < size && IS_BLANK(text[i]); i++);
      i--;
    } else {
      text[pos++] = text[i];
    }
  }

  for (i = pos - 1; 0 < i; i--) {
    if (IS_BLANK(text[i]) || '\0' == text[i]) text[i] = '\0';
    else break;
  }
}

void lex_certificate(Lexer* lex) {
  Token* command_token = NULL;
  char* command_value = NULL;
  Token* indent_token = NULL;
  Token* certificate_token = NULL;

  lex->ts->size -= 2;
  while ((ON_NEWLINE(lex) || ON_SPACE(lex)) && lex->pos < lex->size) lex->pos++;
  lex->token_start = lex->pos;
  finish_token(lex, TOKEN_CERTIFICATE_BEGIN, false);
  lex->indent_levels -= 1;
  lex->indent_columns = lex->indents[lex->indent_levels];

  for (; lex->pos < lex->size; lex->pos++) {
    if (4 < lex->pos - lex->token_start &&
        0 == strncmp("quit", &lex->text[lex->pos - 4], 4)) {
      lex->token_size = lex->pos - lex->token_start - 4;
      certificate_token = finish_token(lex, TOKEN_STRING, true);
      compact_spaces(certificate_token->value);
      lex->pos++;
      lex->token_start = lex->pos;
      finish_token(lex, TOKEN_CERTIFICATE_END, false);
      finish_token(lex, TOKEN_EOL, false);
      while (!ON_NEWLINE(lex) && lex->pos < lex->size) lex->pos++;
      lex->token_start = lex->pos - 1;
      return;
    }
  }
  /* consume characters */
  /* recognize stop sequence */
  /* emit tokens */
  /* reset lexer */
}

void lex_middle_of_line(Lexer* lex) {
  for (; lex->pos < lex->size; lex->pos++) {
    if (on_banner(lex)) {
      lex_banner(lex);
      return;
    } else if (on_certificate(lex)) {
      lex_certificate(lex);
      return;
    } else if (ON_COMMENT(lex)) {
      lex_comment(lex);
      return;
    } else if (ON_NEWLINE(lex)) {
      lex->token_start = lex->pos;
      finish_token(lex, TOKEN_EOL, false);
      return;
    } else if (ON_DECIMAL(lex) && !ON_ZERO(lex)) {
      lex->token_start = lex->pos;
      lex_integer(lex);
    } else if (!ON_SPACE(lex)) {
      lex->token_start = lex->pos;
      lex_string(lex);
    }
  }
}

void lex_start_of_line(Lexer* lex) {
  int current_indent = 0;

  for (; lex->pos < lex->size; lex->pos++) {
    if (ON_LEAD_COMMENT(lex)) {
      if (!lex_indent_update(lex, current_indent)) return;
      current_indent = 0;
      lex_comment(lex);
    } else if (ON_SPACE(lex)) {
      current_indent++;
    } else {
      if (!lex_indent_update(lex, current_indent)) return;
      current_indent = 0;
      lex_middle_of_line(lex);
    }
  }
}

TokenStream* tokenize(char* input_text, int input_size) {
  TokenStream* ts;
  Lexer lex;
  char* value;

  /* allocate and initialize token stream */
  ts = malloc(sizeof(TokenStream));
  ts->size = 0;
  ts->capacity = 100;
  ts->tokens = malloc(ts->capacity * sizeof(Token));

  /* initialize the lexer */
  lex.text = input_text;
  lex.ts = ts;
  lex.size = input_size;
  lex.pos = 0;
  lex.indent_columns = 0;
  lex.indent_levels = 0;
  lex.indents[0] = 0;

  lex_start_of_line(&lex);
  lex_indent_update(&lex, 0);

  return ts;
}

void free_token_stream(TokenStream* ts) {
  int i;

  /* free the value string for each token */
  for (i = 0; i < ts->size; i++) {
    if (ts->tokens[i].value) free(ts->tokens[i].value);
  }

  free(ts->tokens);
  free(ts);
}
