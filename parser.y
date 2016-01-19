%{
/**
 * Introduction to Compiler Design by Prof. Yi Ping You
 * Project 3 YACC sample
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "header.h"
#include "symtab.h"
#include "semcheck.h"

//#include "test.h"

int yydebug;

extern int linenum;		/* declared in lex.l */
extern FILE *yyin;		/* declared by lex */
extern char *yytext;		/* declared by lex */
extern char buf[256];		/* declared in lex.l */
extern int yylex(void);
int yyerror(char* );

FILE* java_file;
char java_cmd[256];
int next_number = 0;

int rel_cnt = 0;
int loop_cnt = 0;
int loop_top = -1;
int loop_stack[256];

int scope = 0;
int Opt_D = 1;			/* symbol table dump option */
char fileName[256];

struct SymTable *symbolTable;	// main symbol table

__BOOLEAN paramError;			// indicate is parameter have any error?

struct PType *funcReturn;		// record function's return type, used at 'return statement' production rule

%}

%union {
	int intVal;
	float realVal;
	//__BOOLEAN booleanVal;
	char *lexeme;
	struct idNode_sem *id;
	//SEMTYPE type;
	struct ConstAttr *constVal;
	struct PType *ptype;
	struct param_sem *par;
	struct expr_sem *exprs;
	/*struct var_ref_sem *varRef; */
	struct expr_sem_node *exprNode;
};

/* tokens */
%token ARRAY BEG BOOLEAN DEF DO ELSE END FALSE FOR INTEGER IF OF PRINT READ REAL RETURN STRING THEN TO TRUE VAR WHILE
%token OP_ADD OP_SUB OP_MUL OP_DIV OP_MOD OP_ASSIGN OP_EQ OP_NE OP_GT OP_LT OP_GE OP_LE OP_AND OP_OR OP_NOT
%token MK_COMMA MK_COLON MK_SEMICOLON MK_LPAREN MK_RPAREN MK_LB MK_RB

%token <lexeme>ID
%token <intVal>INT_CONST 
%token <realVal>FLOAT_CONST
%token <realVal>SCIENTIFIC
%token <lexeme>STR_CONST

%type<id> id_list
%type<constVal> literal_const
%type<ptype> type scalar_type array_type opt_type
%type<par> param param_list opt_param_list
%type<exprs> var_ref boolean_expr boolean_term boolean_factor relop_expr expr term factor boolean_expr_list opt_boolean_expr_list
%type<intVal> dim mul_op add_op rel_op array_index loop_param

/* start symbol */
%start program
%%

program		: ID
			{
				struct PType *pType = createPType( VOID_t );
				struct SymNode *newNode = createProgramNode( $1, scope, pType, -1 );
				insertTab( symbolTable, newNode );
				
				if( strcmp(fileName,$1) ) {
					fprintf( stdout, "########## Error at Line#%d: program beginning ID inconsist with file name ########## \n", linenum );
				}
				//code generate
				fprintf(java_file, ".class public %s\n", newNode->name);
				fprintf(java_file, ".super java/lang/Object\n");
				fprintf(java_file, ".field public static _sc Ljava/util/Scanner;\n");
			}
			MK_SEMICOLON 
			program_body
			END ID
			{
				if( strcmp($1, $6) ) { fprintf( stdout, "########## Error at Line #%d: %s", linenum,"Program end ID inconsist with the beginning ID ########## \n"); }
				if( strcmp(fileName,$6) ) {
					fprintf( stdout, "########## Error at Line#%d: program end ID inconsist with file name ########## \n", linenum );
				}
				// dump symbol table
				if( Opt_D == 1 )
					printSymTable( symbolTable, scope );
				//code generate
				fprintf(java_file, "return\n");
				fprintf(java_file, ".end method\n");
			}
			;

program_body	: opt_decl_list opt_func_decl_list
			{
				//code generate
				fprintf(java_file, ".method public static main([Ljava/lang/String;)V\n");
				fprintf(java_file, ".limit stack 100\n");
				fprintf(java_file, ".limit locals 100\n");
				
				fprintf(java_file, "new java/util/Scanner\n");
				fprintf(java_file, "dup\n");
				fprintf(java_file, "getstatic java/lang/System/in Ljava/io/InputStream;\n");
				fprintf(java_file, "invokespecial java/util/Scanner/<init>(Ljava/io/InputStream;)V\n");
				fprintf(java_file, "putstatic %s/_sc Ljava/util/Scanner;\n", fileName);
				next_number = 1;
			}
			compound_stmt
			;

opt_decl_list	: decl_list
			| 	/* epsilon */
			;

decl_list		: decl_list decl
			| 	decl
			;

decl			: VAR id_list MK_COLON scalar_type MK_SEMICOLON       /* scalar type declaration */
			{
				// insert into symbol table
				struct idNode_sem *ptr;
				struct SymNode *newNode;
				for( ptr=$2 ; ptr!=0 ; ptr=(ptr->next) ) {
					if( verifyRedeclaration( symbolTable, ptr->value, scope ) ==__FALSE ) {
					}
					else {
						if( scope==0 ) {	//global var
							newNode = createVarNode( ptr->value, scope, $4, -1);
							insertTab( symbolTable, newNode );
							//code generate
							fprintf(java_file, ".field public static %s %s\n", newNode->name, java_type(newNode->type) );
						}
						else {	//local var
							newNode = createVarNode( ptr->value, scope, $4, next_number );
							next_number++;
							insertTab( symbolTable, newNode );
						}
					}
				}
				deleteIdList( $2 );
			}
			| VAR id_list MK_COLON array_type MK_SEMICOLON        /* array type declaration */
			{
				verifyArrayType( $2, $4 );
				// insert into symbol table
				struct idNode_sem *ptr;
				struct SymNode *newNode;
				for( ptr=$2 ; ptr!=0 ; ptr=(ptr->next) ) {
					if( $4->isError == __TRUE ) { }
					else if( verifyRedeclaration( symbolTable, ptr->value, scope ) ==__FALSE ) { }
					else {
						newNode = createVarNode( ptr->value, scope, $4, -1);
						insertTab( symbolTable, newNode );
					}
				}
				deleteIdList( $2 );
			}
			| VAR id_list MK_COLON literal_const MK_SEMICOLON     /* const declaration */
			{
				struct PType *pType = createPType( $4->category );
				// insert constants into symbol table
				struct idNode_sem *ptr;
				struct SymNode *newNode;
				for( ptr=$2 ; ptr!=0 ; ptr=(ptr->next) ) {
					if( verifyRedeclaration( symbolTable, ptr->value, scope ) ==__FALSE ) { }
					else {
						newNode = createConstNode( ptr->value, scope, pType, $4, -1);
						insertTab( symbolTable, newNode );
					}
				}
				deleteIdList( $2 );
			}
			;

literal_const	: INT_CONST
			{
				int tmp = $1;
				$$ = createConstAttr( INTEGER_t, &tmp );
			}
			| OP_SUB INT_CONST
			{
				int tmp = -$2;
				$$ = createConstAttr( INTEGER_t, &tmp );
			}
			| FLOAT_CONST
			{
				float tmp = $1;
				$$ = createConstAttr( REAL_t, &tmp );
			}
			| OP_SUB FLOAT_CONST
			{
				float tmp = -$2;
				$$ = createConstAttr( REAL_t, &tmp );
			}
			| SCIENTIFIC 
			{
				float tmp = $1;
				$$ = createConstAttr( REAL_t, &tmp );
			}
			| OP_SUB SCIENTIFIC
			{
				float tmp = -$2;
				$$ = createConstAttr( REAL_t, &tmp );
			}
			| STR_CONST
			{
				$$ = createConstAttr( STRING_t, $1 );
			}
			| TRUE
			{
				__BOOLEAN tmp = __TRUE;
				$$ = createConstAttr( BOOLEAN_t, &tmp );
			}
			| FALSE
			{
				__BOOLEAN tmp = __FALSE;
				$$ = createConstAttr( BOOLEAN_t, &tmp );
			}
			;

opt_func_decl_list	: func_decl_list
			| /* epsilon */
			;

func_decl_list		: func_decl_list func_decl
			| func_decl
			;

func_decl		: ID MK_LPAREN opt_param_list
			{
				// check and insert parameters into symbol table
				paramError = insertParamIntoSymTable( symbolTable, $3, scope+1, &next_number );
			}
			MK_RPAREN opt_type 
			{
				// check and insert function into symbol table
				if( paramError == __TRUE ) {
					printf("--- param(s) with several fault!! ---\n");
				}
				else {
					insertFuncIntoSymTable( symbolTable, $1, $3, $6, scope, java_file );
				}
				funcReturn = $6;
			}
			MK_SEMICOLON
			compound_stmt
			END ID
			{
				if( strcmp($1,$11) ) {
					fprintf( stdout, "########## Error at Line #%d: the end of the functionName mismatch ########## \n", linenum );
				}
				funcReturn = 0;
				//code generate
				fprintf(java_file, "return\n");
				fprintf(java_file, ".end method\n");
			}
			;

opt_param_list	: param_list { $$ = $1; }
			| /* epsilon */ { $$ = 0; }
			;

param_list		: param_list MK_SEMICOLON param
			{
				param_sem_addParam( $1, $3 );
				$$ = $1;
			}
			| param { $$ = $1; }
			;

param			: id_list MK_COLON type { $$ = createParam( $1, $3 ); }
			;

id_list			: id_list MK_COMMA ID
			{
				idlist_addNode( $1, $3 );
				$$ = $1;
			}
			| ID 
			{ 
				$$ = createIdList($1);
			}
			;

opt_type		: MK_COLON type { $$ = $2; }
			| /* epsilon */ { $$ = createPType( VOID_t ); }
			;

type			: scalar_type { $$ = $1; }
			| array_type { $$ = $1; }
			;

scalar_type		: INTEGER { $$ = createPType( INTEGER_t ); }
			| REAL { $$ = createPType( REAL_t ); }
			| BOOLEAN { $$ = createPType( BOOLEAN_t ); }
			| STRING { $$ = createPType( STRING_t ); }
			;

array_type		: ARRAY array_index TO array_index OF type
			{
				verifyArrayDim( $6, $2, $4 );
				increaseArrayDim( $6, $2, $4 );
				$$ = $6;
			}
			;

array_index		: INT_CONST { $$ = $1; }
			| OP_SUB INT_CONST { $$ = -$2; }
			;

stmt			: compound_stmt
			| simple_stmt
			| cond_stmt
			| while_stmt
			| for_stmt
			| return_stmt
			| proc_call_stmt
			;

compound_stmt		: 
			{ 
				scope++;
			}
			BEG
			opt_decl_list
			opt_stmt_list
			END 
			{ 
				// print contents of current scope
				if( Opt_D == 1 )
					printSymTable( symbolTable, scope );
				deleteScope( symbolTable, scope );	// leave this scope, delete...
				scope--; 
			}
			;

opt_stmt_list		: stmt_list
			| /* epsilon */
			;

stmt_list		: stmt_list stmt
			| stmt
			;

simple_stmt		: var_ref OP_ASSIGN boolean_expr MK_SEMICOLON
			{
				// check if LHS exists
				__BOOLEAN flagLHS = verifyExistence( symbolTable, $1, scope, __TRUE );
				// id RHS is not dereferenced, check and deference
				__BOOLEAN flagRHS = __TRUE;
				if( $3->isDeref == __FALSE ) {
					flagRHS = verifyExistence( symbolTable, $3, scope, __FALSE );
				}
				// if both LHS and RHS are exists, verify their type
				if( flagLHS==__TRUE && flagRHS==__TRUE )
					verifyAssignmentTypeMatch( $1, $3 );
				//code generate
				struct SymNode *node = lookupSymbol( symbolTable, $1->varRef->id, scope, __FALSE );
				if( node->scope==0 )
				{
					fprintf(java_file, "putstatic %s/%s %s\n", fileName, node->name, java_type(node->type) );
				}
				else
				{
					if( $1->pType->type==INTEGER_t || $1->pType->type==BOOLEAN_t )
					{
						fprintf(java_file, "istore %d\n", node->next_num);
					}
					else if( $1->pType->type==REAL_t )
					{
						if( $3->pType->type==INTEGER_t || $3->pType->type==BOOLEAN_t )
						{
							fprintf(java_file, "i2f\n");
						}
						fprintf(java_file, "fstore %d\n", node->next_num);
					}
				}
			}
			| PRINT
			{
				fprintf(java_file, "getstatic java/lang/System/out Ljava/io/PrintStream;\n");
			}
			boolean_expr MK_SEMICOLON 
			{
				verifyScalarExpr( $3, "print" );
				switch( $3->pType->type )
				{
					case INTEGER_t:
						fprintf(java_file, "invokevirtual java/io/PrintStream/print(I)V\n");
					break;
					case BOOLEAN_t:
						fprintf(java_file, "invokevirtual java/io/PrintStream/print(I)V\n");
					break;
					case REAL_t:
						fprintf(java_file, "invokevirtual java/io/PrintStream/print(F)V\n");
					break;
					case STRING_t:
						fprintf(java_file, "invokevirtual java/io/PrintStream/print(Ljava/lang/String;)V\n");
					break;
					default:
						fprintf(java_file, "invokevirtual java/io/PrintStream/print(I)V\n");
					break;
				}
			}
 			| READ var_ref MK_SEMICOLON
			{
				struct SymNode *node = lookupLoopVar( symbolTable, $2->varRef->id );
				if( node == 0 ) {
					node = lookupSymbol( symbolTable, $2->varRef->id, scope, __FALSE );
				}
				
				//verifyScalarExpr( $2, "read" );
				//code generate
				switch( node->type->type )
				{
					case INTEGER_t:
						fprintf(java_file, "getstatic test/_sc Ljava/util/Scanner;\n");
						fprintf(java_file, "invokevirtual java/util/Scanner/nextInt()I\n");
					break;
					case BOOLEAN_t:
						fprintf(java_file, "getstatic test/_sc Ljava/util/Scanner;\n");
						fprintf(java_file, "invokevirtual java/util/Scanner/nextBoolean()Z\n");
					break;
					case REAL_t:
						fprintf(java_file, "getstatic test/_sc Ljava/util/Scanner;\n");
						fprintf(java_file, "invokevirtual java/util/Scanner/nextFloat()F\n");
					break;
				}
				
				if( node->scope==0 )
				{
					fprintf(java_file, "putstatic %s/%s %s\n", fileName, node->name, java_type(node->type) );
				}
				else
				{
					if( node->type->type==INTEGER_t )
						fprintf(java_file, "istore %d\n", node->next_num);
					else if( node->type->type==REAL_t )
						fprintf(java_file, "fstore %d\n", node->next_num);
				}
			}
			;

proc_call_stmt	: ID MK_LPAREN opt_boolean_expr_list MK_RPAREN MK_SEMICOLON
			{
				verifyFuncInvoke( $1, $3, symbolTable, scope );
				//code generate
				struct PTypeList *listPtr;	// = node->attribute->formalParam->params;
				struct SymNode *node = lookupSymbol( symbolTable, $1, 0, __FALSE );
				fprintf( java_file, "invokestatic %s/%s(", fileName, $1 ); 
				for( listPtr=(node->attribute->formalParam->params); listPtr!=0; listPtr=(listPtr->next) )
				{
					fprintf(java_file, "%s", java_type(listPtr->value) );
				}
				fprintf( java_file, ")%s\n", java_type(node->type) );
			}
			;

cond_stmt		: IF
			condition THEN
			{
				loop_top++;
				loop_stack[loop_top] = loop_cnt;
				loop_cnt++;
				fprintf(java_file, "ifeq Lfalse%d\n", loop_stack[loop_top]);
			}
			opt_stmt_list
			ELSE
			{
				fprintf(java_file, "goto Lexit%d\n", loop_stack[loop_top]);
				fprintf(java_file, "Lfalse%d:\n", loop_stack[loop_top]);
			}
			opt_stmt_list
			END IF
			{
				fprintf(java_file, "Lexit%d:\n", loop_stack[loop_top]);
				loop_top--;
			}
			| IF condition THEN
			{
				loop_top++;
				loop_stack[loop_top] = loop_cnt;
				loop_cnt++;
				fprintf(java_file, "ifeq Lfalse%d\n", loop_stack[loop_top]);
			}
			opt_stmt_list END IF
			{
				fprintf(java_file, "Lfalse%d:\n", loop_stack[loop_top]);
				fprintf(java_file, "Lexit%d:\n", loop_stack[loop_top]);
				loop_top--;
			}
			;

condition		: boolean_expr { verifyBooleanExpr( $1, "if" ); } 
			;

while_stmt		: WHILE
			{	
				loop_top++;
				loop_stack[loop_top] = loop_cnt;
				loop_cnt++;
				fprintf(java_file, "Lbegin%d:\n", loop_stack[loop_top]);
			}
			condition_while DO
			{
				fprintf(java_file, "ifeq Lexit%d\n", loop_stack[loop_top]);
			}
			opt_stmt_list
			END DO
			{
				fprintf(java_file, "goto Lbegin%d\n", loop_stack[loop_top]);
				fprintf(java_file, "Lexit%d:\n", loop_stack[loop_top]);
				loop_top--;
			}
			;

condition_while		: boolean_expr { verifyBooleanExpr( $1, "while" ); } 
			;

for_stmt		: FOR ID 
			{ 
				insertLoopVarIntoTable( symbolTable, $2 );
			}
			OP_ASSIGN loop_param TO loop_param DO
			{
				verifyLoopParam( $5, $7 );
				//code generate
				loop_top++;
				loop_stack[loop_top] = loop_cnt;
				loop_cnt++;
				struct SymNode *node = lookupSymbol( symbolTable, $2, scope, __FALSE );
				fprintf(java_file, "ldc %d\n", $5);
				fprintf(java_file, "istore %d\n", node->next_num);
				
				fprintf(java_file, "Lbegin%d:\n", loop_stack[loop_top]);
				fprintf(java_file, "iload %d\n", node->next_num);
				fprintf(java_file, "ldc %d\n", $7);
				fprintf(java_file, "isub\n");
				fprintf(java_file, "ifgt Lexit%d\n", loop_stack[loop_top]);
			}
			opt_stmt_list
			END DO
			{
				//code generate
				struct SymNode *node = lookupSymbol( symbolTable, $2, scope, __FALSE );
				fprintf(java_file, "iload %d\n", node->next_num);
				fprintf(java_file, "ldc 1\n");
				fprintf(java_file, "iadd\n");
				fprintf(java_file, "istore %d\n", node->next_num);
				fprintf(java_file, "goto Lbegin%d\n", loop_stack[loop_top]);
				fprintf(java_file, "Lexit%d:\n", loop_stack[loop_top]);
				loop_top--;
				
				popLoopVar( symbolTable );
			}
			;

loop_param		: INT_CONST { $$ = $1; }
			| OP_SUB INT_CONST { $$ = -$2; }
			;

return_stmt		: RETURN boolean_expr MK_SEMICOLON
			{
				verifyReturnStatement( $2, funcReturn );
				//code generate
				fprintf(java_file, "%sreturn\n", lower_java_type(funcReturn) );
			}
			;

opt_boolean_expr_list	: boolean_expr_list { $$ = $1; }
			| /* epsilon */ { $$ = 0; }	// null
			;

boolean_expr_list	: boolean_expr_list MK_COMMA boolean_expr
			{
				struct expr_sem *exprPtr;
				for( exprPtr=$1 ; (exprPtr->next)!=0 ; exprPtr=(exprPtr->next) );
				exprPtr->next = $3;
				$$ = $1;
			}
			| boolean_expr
			{
				$$ = $1;
			}
			;

boolean_expr	: boolean_expr OP_OR boolean_term
			{
				verifyAndOrOp( $1, OR_t, $3 );
				$$ = $1;
				//code generate
				fprintf(java_file, "ior\n"); 
			}
			| boolean_term { $$ = $1; }
			;

boolean_term	: boolean_term OP_AND boolean_factor
			{
				verifyAndOrOp( $1, AND_t, $3 );
				$$ = $1;
				//code generate
				fprintf(java_file, "iand\n"); 
			}
			| boolean_factor { $$ = $1; }
			;

boolean_factor		: OP_NOT boolean_factor 
			{
				verifyUnaryNOT( $2 );
				$$ = $2;
				//code generate
				fprintf(java_file, "iconst_1\n");
				fprintf(java_file, "ixor\n"); 
			}
			| relop_expr { $$ = $1; }
			;

relop_expr		: expr rel_op expr
			{
				verifyRelOp( $1, $2, $3 );
				$$ = $1;
				//code generate
				if( $1->pType->type==REAL_t )
				{
					if( $3->pType->type==REAL_t )
					{
						fprintf(java_file, "fcmpl\n");
					}
					else
					{
						fprintf(java_file, "i2f\n");
						fprintf(java_file, "fcmpl\n");
					}
				}
				else
				{
					if( $3->pType->type==REAL_t )
					{
						fprintf(java_file, "fstore 99\n");
						fprintf(java_file, "i2f\n");
						fprintf(java_file, "fload 99\n");
						fprintf(java_file, "fcmpl\n");
					}
					else
					{
						fprintf(java_file, "isub\n");
					}
				}
				
				switch( $2 )
				{
					case LT_t:
						fprintf(java_file, "iflt ");
					break;
					case LE_t:
						fprintf(java_file, "ifle ");
					break;
					case EQ_t:
						fprintf(java_file, "ifeq ");
					break;
					case GE_t:
						fprintf(java_file, "ifge ");
					break;
					case GT_t:
						fprintf(java_file, "ifgt ");
					break;
					case NE_t:
						fprintf(java_file, "ifne ");
					break;
				}
				fprintf(java_file, "L%d\n", rel_cnt);
				fprintf(java_file, "iconst_0\n");
				fprintf(java_file, "goto L%d\n", rel_cnt+1);
				fprintf(java_file, "L%d:\n", rel_cnt);
				fprintf(java_file, "iconst_1\n");
				fprintf(java_file, "L%d:\n", rel_cnt+1);
				rel_cnt += 2;
			}
			| expr { $$ = $1; }
			;

rel_op			: OP_LT { $$ = LT_t; }
			| OP_LE { $$ = LE_t; }
			| OP_EQ { $$ = EQ_t; }
			| OP_GE { $$ = GE_t; }
			| OP_GT { $$ = GT_t; }
			| OP_NE { $$ = NE_t; }
			;

expr			: expr add_op term
			{
				//code generate
				if( $1->pType->type==REAL_t )
				{
					if( $3->pType->type==REAL_t )
					{
						fprintf(java_file, "f");
					}
					else
					{
						fprintf(java_file, "i2f\n");
						fprintf(java_file, "f");
					}
				}
				else
				{
					if( $3->pType->type==REAL_t )
					{
						fprintf(java_file, "fstore 99\n");
						fprintf(java_file, "i2f\n");
						fprintf(java_file, "fload 99\n");
						fprintf(java_file, "f");
					}
					else
					{
						fprintf(java_file, "i");
					}
				}
				
				if( $2==ADD_t )
					fprintf(java_file, "add\n");
				else
					fprintf(java_file, "sub\n");
				
				verifyArithmeticOp( $1, $2, $3 );
				$$ = $1;
			}
			| term { $$ = $1; }
			;

add_op			: OP_ADD { $$ = ADD_t; }
			| OP_SUB { $$ = SUB_t; }
			;

term			: term mul_op factor
			{
				if( $2 == MOD_t ) 
				{
					verifyModOp( $1, $3 );
					//code generate
					fprintf(java_file, "irem\n");
				}
				else {
					//code generate
					if( $1->pType->type==REAL_t )
					{
						if( $3->pType->type==REAL_t )
						{
							fprintf(java_file, "f");
						}
						else
						{
							fprintf(java_file, "i2f\n");
							fprintf(java_file, "f");
						}
					}
					else
					{
						if( $3->pType->type==REAL_t )
						{
							fprintf(java_file, "fstore 99\n");
							fprintf(java_file, "i2f\n");
							fprintf(java_file, "fload 99\n");
							fprintf(java_file, "f");
						}
						else
						{
							fprintf(java_file, "i");
						}
					}
					
					if( $2==MUL_t )
						fprintf(java_file, "mul\n");
					else
						fprintf(java_file, "div\n");
					
					verifyArithmeticOp( $1, $2, $3 );
				}
				$$ = $1;
			}
			| factor { $$ = $1; }
			;

mul_op			: OP_MUL { $$ = MUL_t; }
			| OP_DIV { $$ = DIV_t; }
			| OP_MOD { $$ = MOD_t; }
			;

factor			: var_ref
			{
				verifyExistence( symbolTable, $1, scope, __FALSE );
				$$ = $1;
				$$->beginningOp = NONE_t;
				//code generate
				load_var( symbolTable, $1, scope, fileName, java_file );
			}
			| OP_SUB var_ref
			{
				if( verifyExistence( symbolTable, $2, scope, __FALSE ) == __TRUE )
					verifyUnaryMinus( $2 );
				$$ = $2;
				$$->beginningOp = SUB_t;
				//code generate
				load_var( symbolTable, $2, scope, fileName, java_file );
				fprintf(java_file, "%sneg\n", java_type2($2->pType));
			}
			| MK_LPAREN boolean_expr MK_RPAREN 
			{
				$2->beginningOp = NONE_t;
				$$ = $2; 
			}
			| OP_SUB MK_LPAREN boolean_expr MK_RPAREN
			{
				verifyUnaryMinus( $3 );
				$$ = $3;
				$$->beginningOp = SUB_t;
				//code generate
				fprintf(java_file, "%sneg\n", java_type2($3->pType));
			}
			| ID MK_LPAREN opt_boolean_expr_list MK_RPAREN
			{
				
				$$ = verifyFuncInvoke( $1, $3, symbolTable, scope );
				$$->beginningOp = NONE_t;
				//code generate
				struct PTypeList *listPtr;	// = node->attribute->formalParam->params;
				struct SymNode *node = lookupSymbol( symbolTable, $1, 0, __FALSE );
				fprintf( java_file, "invokestatic %s/%s(", fileName, $1 ); 
				for( listPtr=(node->attribute->formalParam->params); listPtr!=0; listPtr=(listPtr->next) )
				{
					fprintf(java_file, "%s", java_type(listPtr->value) );
				}
				fprintf( java_file, ")%s\n", java_type(node->type) );
			}
			| OP_SUB ID MK_LPAREN opt_boolean_expr_list MK_RPAREN
			{
				$$ = verifyFuncInvoke( $2, $4, symbolTable, scope );
				$$->beginningOp = SUB_t;
				//code generate
				struct PTypeList *listPtr;	// = node->attribute->formalParam->params;
				struct SymNode *node = lookupSymbol( symbolTable, $2, 0, __FALSE );
				fprintf( java_file, "invokestatic %s/%s(", fileName, $2 ); 
				for( listPtr=(node->attribute->formalParam->params); listPtr!=0; listPtr=(listPtr->next) )
				{
					fprintf(java_file, "%s", java_type(listPtr->value) );
				}
				fprintf( java_file, ")%s\n", java_type(node->type) );
				fprintf(java_file, "%sneg\n", java_type2(node->type) );
			}
			| literal_const
			{
				$$ = (struct expr_sem *)malloc(sizeof(struct expr_sem));
				$$->isDeref = __TRUE;
				$$->varRef = 0;
				$$->pType = createPType( $1->category );
				$$->next = 0;
				if( $1->hasMinus == __TRUE ) {
					$$->beginningOp = SUB_t;
				}
				else {
					$$->beginningOp = NONE_t;
				}
				//code generate
				switch( $1->category )
				{
					case INTEGER_t:
						fprintf(java_file, "ldc %d\n", $1->value.integerVal);
					break;
					case BOOLEAN_t:
						if( ($1->value).booleanVal==__TRUE )
							fprintf(java_file, "iconst_1\n");
						else
							fprintf(java_file, "iconst_0\n");
					break;
					case STRING_t:
						fprintf(java_file, "ldc \"%s\"\n", ($1->value).stringVal);
					break;
					case REAL_t:
						fprintf(java_file, "ldc %f\n", ($1->value).realVal);
					break;
					default:
						/* FIXME */
					break;
				}
			}
			;

var_ref			: ID
			{
				$$ = createExprSem( $1 );
			}
			| var_ref dim
			{
				increaseDim( $1, $2 );
				$$ = $1;
			}
			;

dim			: MK_LB boolean_expr MK_RB
			{
				$$ = verifyArrayIndex( $2 );
			}
			;

%%

int yyerror( char *msg )
{
	(void) msg;
	fprintf( stderr, "\n|--------------------------------------------------------------------------\n" );
	fprintf( stderr, "| Error found in Line #%d: %s\n", linenum, buf );
	fprintf( stderr, "|\n" );
	fprintf( stderr, "| Unmatched token: %s\n", yytext );
	fprintf( stderr, "|--------------------------------------------------------------------------\n" );
	exit(-1);
}

