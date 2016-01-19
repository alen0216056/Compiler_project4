#ifndef _SYMTAB_H_
#define _SYMTAB_H_
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "header.h"

//#define HASHBUNCH 1

void initSymTab( struct SymTable *table );
int hashFunc( const char *str );
void insertTab( struct SymTable *table, struct SymNode *newNode );
void pushLoopVar( struct SymTable *table, struct SymNode *newNode );
void popLoopVar( struct SymTable *table );
struct SymNode *createLoopVarNode( const char *name );
struct SymNode* createVarNode( const char *name, int scope, struct PType *type, int _next_num );
struct SymNode* createParamNode( const char *name, int scope, struct PType *type, int _next_num );
//struct SymNode* createVarNode( const char *name, int scope, struct PType *type ); 
struct SymNode * createConstNode( const char *name, int scope, struct PType *pType, struct ConstAttr *constAttr, int _next_num);
struct SymNode *createFuncNode( const char *name, int scope, struct PType *pType, struct FuncAttr *params );
//struct SymNode *createProgramNode( const char *name, int scope );
struct SymNode *createProgramNode( const char *name, int scope, struct PType *pType, int _next_num );

struct SymNode *lookupSymbol( struct SymTable *table, const char *id, int scope, __BOOLEAN currentScope );
struct SymNode *lookupLoopVar( struct SymTable *table, const char *id );

void deleteSymbol( struct SymNode *symbol );
void deleteScope( struct SymTable *table, int scope );

void printType( struct PType *type, int flag ); 
void dumpSymTable( struct SymTable *table );
void printSymTable( struct SymTable *table, int __scope );

//alen
char* java_type( struct PType *type );
char* java_type2( struct PType *type );
char* lower_java_type( struct PType *type );
void load_var( struct SymTable *table, struct expr_sem *expr, int scope, char* fileName, FILE* java_file );
#endif

