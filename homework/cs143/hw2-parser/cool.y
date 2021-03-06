/*
 *  cool.y
 *              Parser definition for the COOL language.
 *
 */
%{
#include <iostream>
#include "cool-tree.h"
#include "stringtab.h"
#include "utilities.h"

#include <list>

#ifdef yylineno
#undef yylineno
#endif //yylineno

extern char *curr_filename;

void yyerror(char *s);        /*  defined below; called for each parse error */
extern int yylex();           /*  the entry point to the lexer  */


Expression makeDefaultExpression(Symbol ofType);

 struct Letvar {
   Letvar (Symbol i, Symbol t, Expression e) {id=i; type=t; expr=e; }
   Symbol id;
   Symbol type;
   Expression expr;
 };

template <class T>  List<T> * list_nth(List<T> *l, int index);


typedef List<Letvar> * Letvars;

/************************************************************************/
/*                DONT CHANGE ANYTHING IN THIS SECTION                  */


Program ast_root;	      /* the result of the parse  */
Classes parse_results;        /* for use in semantic analysis */
int omerrs = 0;               /* number of errors in lexing and parsing */
%}

/* A union of all the types that can be the result of parsing actions. */
%union {
  Boolean boolean;
  Symbol symbol;
  Program program;
  Class_ class_;
  Classes classes;
  Feature feature;
  Features features;
  Formal formal;
  Formals formals;
  Case case_;
  Cases cases;
  Expression expression;
  Expressions expressions;
  Letvar * letvar;
  Letvars letvars;
  char *error_msg;
}

/* 
   Declare the terminals; a few have types for associated lexemes.
   The token ERROR is never used in the parser; thus, it is a parse
   error when the lexer returns it.

   The integer following token declaration is the numeric constant used
   to represent that token internally.  Typically, Bison generates these
   on its own, but we give explicit numbers to prevent version parity
   problems (bison 1.25 and earlier start at 258, later versions -- at
   257)
*/
%token CLASS 258 ELSE 259 FI 260 IF 261 IN 262 
%token INHERITS 263 LET 264 LOOP 265 POOL 266 THEN 267 WHILE 268
%token CASE 269 ESAC 270 OF 271 DARROW 272 NEW 273 ISVOID 274
%token <symbol>  STR_CONST 275 INT_CONST 276 
%token <boolean> BOOL_CONST 277
%token <symbol>  TYPEID 278 OBJECTID 279 
%token ASSIGN 280 NOT 281 LE 282 ERROR 283

/*  DON'T CHANGE ANYTHING ABOVE THIS LINE, OR YOUR PARSER WONT WORK       */
/**************************************************************************/
 
   /* Complete the nonterminal list below, giving a type for the semantic
      value of each non terminal. (See section 3.6 in the bison 
      documentation for details). */

/* Declare types for the grammar's non-terminals. */
%type <program> program
%type <classes> class_list
%type <class_> class

/* You will want to change the following line. */
%type <features> feature_list
%type <features> nonempty_feature_list
%type <feature> feature
%type <expression> expr
%type <expressions> oneormore_expr;
%type <expressions> comma_delimited_exprs;
%type <formals> method_formals;
%type <formal> formal;
%type <cases> case_branches;
%type <case_> case_branch;
%type <letvar>  letvar;
%type <letvars> letvars;
/*%type <error_msg> syntax_error; */

/* Precedence declarations go here. */

%left LETPREC
%right ASSIGN
%left NOT
%nonassoc LE '<' '='
%left '+' '-'
%left '*' '/'
%left ISVOID
%left '~'
%left '@'
%left '.'

%%
/* 
   Save the root of the abstract syntax tree in a global variable.
*/
program	: class_list	{ ast_root = program($1); }
;

class_list
: class			/* single class */
{
  // $1 will be NULL when it encountered a parse error
  if ($1)
    {
      $$ = single_Classes($1);
      parse_results = $$;
    }
  else
      $$ = NULL;
}
| class_list class	/* several classes */
{
  if ($1 && $2)
    {
      $$ = append_Classes($1,single_Classes($2)); 
      parse_results = $$;
    }
  else if ($1)
    $$ = $1;
  else if ($2)
    $$ = single_Classes($2);
  else
      $$ = nil_Classes();
}
;

/* If no parent is specified, the class inherits from the Object class. */
class	: 
CLASS TYPEID '{' feature_list '}' ';'
{ $$ = class_($2,idtable.add_string("Object"),$4,
              stringtable.add_string(curr_filename)); }
| CLASS TYPEID INHERITS TYPEID '{' feature_list '}' ';'
{ $$ = class_($2,$4,$6,stringtable.add_string(curr_filename)); }
| CLASS TYPEID '{' error '}' ';' { yyclearin; $$ = NULL; }
| CLASS error '{' feature_list '}' ';' { yyclearin; $$ = NULL;}
| CLASS error '{' error '}' ';' { yyclearin; $$ = NULL;}
;

/* Feature list may be empty, but no empty features in list. */
feature_list :
/* > 0 features */
nonempty_feature_list { $$ = $1 != NULL ? $1 : nil_Features(); }
/* empty */
| {  $$ = nil_Features(); }
;

nonempty_feature_list :
/* single feature */
feature {
  if ($1)
    $$ = single_Features($1);
  else
    $$ = NULL;
}
/* many features */
| nonempty_feature_list feature {
  if ($1 && $2)
    $$ = append_Features($1, single_Features($2));
  else if ($1)
    $$ = $1;
  else if ($2)
    $$ = single_Features($2);
  else
    $$ = NULL;
}
;

feature:
/* method declaration */
OBJECTID '(' method_formals ')' ':' TYPEID '{' expr '}' ';'
{ $$ = method($1, $3, $6, $8); }
/* attribute without assignment */
| OBJECTID ':' TYPEID ';' { $$ = attr($1, $3, makeDefaultExpression($3)); }
/* attribute with assignment */
| OBJECTID ':' TYPEID ASSIGN expr ';' { $$ = attr($1, $3, $5); }
| error { yyclearin; $$ = NULL; }
;

formal:
OBJECTID ':' TYPEID { $$ = formal($1, $3); }
;

method_formals:
formal { $$ = single_Formals($1); }
| method_formals ',' formal { $$ = append_Formals($1, single_Formals($3));}
| { $$ = nil_Formals(); }
;

expr:
OBJECTID ASSIGN expr { $$ = assign($1, $3); } 
/* static dispatch */
| expr '@' TYPEID '.' OBJECTID '(' comma_delimited_exprs ')'
{ $$ = static_dispatch($1, $3, $5, $7); }
/* non-static dispatch */
| expr '.' OBJECTID '(' comma_delimited_exprs ')'
{ $$ = dispatch($1, $3, $5); }
/* omitted 'self' dispatch */
| OBJECTID '(' comma_delimited_exprs ')'
{ $$ =  dispatch(object(idtable.add_string("self")), $1, $3);}

/* if then else fi */
| IF expr THEN expr ELSE expr FI { $$ =  cond($2, $4, $6);}
/* loop */
| WHILE expr LOOP expr POOL { $$ =  loop($2, $4);}

/* blocks */
| '{' oneormore_expr '}' { $$ =  block($2);}

/* let
| LET OBJECTID ':' TYPE ASSIGN expr  IN expr
{ $$ = LET $1 ':' $4 ASSIGN $6 IN }
 */

| LET letvars IN expr %prec LETPREC
{
  // $2 is NULL if an error was encountered while parsing the args
  if ($2)
    {
      List<Letvar> * vars = $2;
      int num_vars = list_length(vars);
      
      // store the next-inner expression here
      // decrement this as we go through the list until it, using it
      // as the next let body, until it is the outter-most expression
      Expression inner_expr = NULL;
      
      // go through each let variable and create a new
      // binding (let expression)
      for (int i = num_vars-1; i >= 0; i--)
        {
          List<Letvar> * item = list_nth(vars, i);
          
          Expression body = inner_expr == NULL ? $4 : inner_expr;
          
          inner_expr = let(item->hd()->id,
                           item->hd()->type,
                           item->hd()->expr,
                           body);
        }
      $$ = inner_expr;
    }
  else
    {
      YYERROR; //signal error if there are no valid lets
      cerr << "signaling an error" << endl;
    }
}
/*

| LET OBJECTID ':' TYPEID IN expr
{ $$ = let($2, $4, no_expr(), $6); }


| LET OBJECTID ':' TYPE ASSIGN expr 
| LET OBJECTID ':' TYPE 
 */

/* case */
| CASE expr OF case_branches ESAC
{ $$ = typcase($2, $4); }

/* special prefix forms */
| NEW TYPEID { $$ = new_($2); }
| ISVOID expr { $$ = isvoid($2); }

/* infix + arithmetic */
| expr '+' expr { $$ = plus($1, $3); }
| expr '-' expr { $$ = sub($1, $3); }
| expr '*' expr { $$ = mul($1, $3); }
| expr '/' expr { $$ = divide($1, $3); }

/* ~negation */
| '~' expr { $$ = neg($2); }

/* infix < comparison */
| expr '<' expr { $$ = lt($1, $3); }
| expr LE expr { $$ = leq($1, $3); } 
| expr '=' expr { $$ = eq($1, $3); }
| NOT expr { $$ = comp($2); }

/* ((((grouping)))) */
| '(' expr ')' { $$ = $2; }

/* literals */
| OBJECTID { $$ = object($1); }
| INT_CONST { $$ = int_const($1);  }
| STR_CONST { $$ = string_const($1); }
| BOOL_CONST { $$ = bool_const($1); }
;

case_branches : case_branch { $$ = single_Cases($1); }
| case_branches case_branch { $$ = append_Cases($1, single_Cases($2));}
;

case_branch : OBJECTID ':' TYPEID DARROW expr ';'
{ $$ = branch($1, $3, $5); }

oneormore_expr :
expr ';' { $$ = single_Expressions($1); }
| oneormore_expr expr ';' { $$ = append_Expressions($1, single_Expressions($2)); }
;

comma_delimited_exprs:
 expr { $$ = single_Expressions($1); }
 | comma_delimited_exprs ',' expr { $$ = append_Expressions($1, single_Expressions($3)); }
|  {$$ = nil_Expressions(); }
;

letvar :
OBJECTID ':' TYPEID ASSIGN expr { $$ = new Letvar($1, $3, $5); }
| OBJECTID ':' TYPEID {$$ = new Letvar($1, $3, no_expr()); }
| error { yyclearin; yyerrok; $$ = NULL; }
;

letvars : letvar {
  // if $1 is null there was an error in parsing
  if ($1)
    $$ = new List<Letvar>($1);
  else
      $$ = NULL;
}
| letvar ',' letvars 
{
  if ($1)
    $$ = new List<Letvar>($1, $3);
  else if ($3)
    $$ = $3;
  else
    $$ = NULL;
}
| letvar error { yyclearin; yyerrok; $$ = new List<Letvar>($1, NULL); }

/*
let_term :
OBJECTID ':' TYPEID ASSIGN expr { $$ = l }
;
*/

/* end of grammar */
%%

/* makes a new expression with the correct default value for the given type. */
Expression makeDefaultExpression(Symbol ofType)
{
  if (strcmp(ofType->get_string(), "Bool") == 0)
    return bool_const(false);

  else if (strcmp(ofType->get_string(), "Int") == 0)
    return int_const(inttable.add_string("0"));

  else if (strcmp(ofType->get_string(), "String") == 0)
    return string_const(stringtable.add_string(""));

  else
    return no_expr();
}

/* This function is called automatically when Bison detects a parse error. */
void yyerror(char *s)
{
  extern int curr_lineno;

  cerr << "\"" << curr_filename << "\", line " << curr_lineno << ": " \
    << s << " at or near ";
  print_cool_token(yychar);
  cerr << endl;
  omerrs++;
  omerrs--;

  if(omerrs>50) {fprintf(stdout, "More than 50 errors\n"); exit(1);}
}


//gets the nth item from the list
template <class T>
  List<T> * list_nth(List<T> *l, int index)
{
  int i = 0;
  for (; l != NULL; l = l->tl())
    if (i++ == index)
      return l;
  return NULL;
}
