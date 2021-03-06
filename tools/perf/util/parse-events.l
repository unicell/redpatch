
%option reentrant
%option bison-bridge
%option prefix="parse_events_"
%option stack

%{
#include <errno.h>
#include "../perf.h"
#include "parse-events-bison.h"
#include "parse-events.h"

char *parse_events_get_text(yyscan_t yyscanner);
YYSTYPE *parse_events_get_lval(yyscan_t yyscanner);

static int __value(YYSTYPE *yylval, char *str, int base, int token)
{
	long num;

	errno = 0;
	num = strtoul(str, NULL, base);
	if (errno)
		return PE_ERROR;

	yylval->num = num;
	return token;
}

static int value(yyscan_t scanner, int base)
{
	YYSTYPE *yylval = parse_events_get_lval(scanner);
	char *text = parse_events_get_text(scanner);

	return __value(yylval, text, base, PE_VALUE);
}

static int raw(yyscan_t scanner)
{
	YYSTYPE *yylval = parse_events_get_lval(scanner);
	char *text = parse_events_get_text(scanner);

	return __value(yylval, text + 1, 16, PE_RAW);
}

static int str(yyscan_t scanner, int token)
{
	YYSTYPE *yylval = parse_events_get_lval(scanner);
	char *text = parse_events_get_text(scanner);

	yylval->str = strdup(text);
	return token;
}

static int sym(yyscan_t scanner, int type, int config)
{
	YYSTYPE *yylval = parse_events_get_lval(scanner);

	yylval->num = (type << 16) + config;
	return type == PERF_TYPE_HARDWARE ? PE_VALUE_SYM_HW : PE_VALUE_SYM_SW;
}

static int term(yyscan_t scanner, int type)
{
	YYSTYPE *yylval = parse_events_get_lval(scanner);

	yylval->num = type;
	return PE_TERM;
}

%}

%x mem
%s config
%x event

group		[^,{}/]*[{][^}]*[}][^,{}/]*
event_pmu	[^,{}/]+[/][^/]*[/][^,{}/]*
event		[^,{}/]+

num_dec		[0-9]+
num_hex		0x[a-fA-F0-9]+
num_raw_hex	[a-fA-F0-9]+
name		[a-zA-Z_*?][a-zA-Z0-9_*?]*
modifier_event	[ukhpGH]{1,8}
modifier_bp	[rwx]{1,3}

%%

%{
	{
		int start_token;

		start_token = parse_events_get_extra(yyscanner);

		if (start_token == PE_START_TERMS)
			BEGIN(config);
		else if (start_token == PE_START_EVENTS)
			BEGIN(event);

		if (start_token) {
			parse_events_set_extra(NULL, yyscanner);
			return start_token;
		}
         }
%}

<event>{

{group}		{
			BEGIN(INITIAL); yyless(0);
		}

{event_pmu}	|
{event}		{
			str(yyscanner, PE_EVENT_NAME);
			BEGIN(INITIAL); yyless(0);
			return PE_EVENT_NAME;
		}

.		|
<<EOF>>		{
			BEGIN(INITIAL); yyless(0);
		}

}

cpu-cycles|cycles				{ return sym(yyscanner, PERF_TYPE_HARDWARE, PERF_COUNT_HW_CPU_CYCLES); }
stalled-cycles-frontend|idle-cycles-frontend	{ return sym(yyscanner, PERF_TYPE_HARDWARE, PERF_COUNT_HW_STALLED_CYCLES_FRONTEND); }
stalled-cycles-backend|idle-cycles-backend	{ return sym(yyscanner, PERF_TYPE_HARDWARE, PERF_COUNT_HW_STALLED_CYCLES_BACKEND); }
instructions					{ return sym(yyscanner, PERF_TYPE_HARDWARE, PERF_COUNT_HW_INSTRUCTIONS); }
cache-references				{ return sym(yyscanner, PERF_TYPE_HARDWARE, PERF_COUNT_HW_CACHE_REFERENCES); }
cache-misses					{ return sym(yyscanner, PERF_TYPE_HARDWARE, PERF_COUNT_HW_CACHE_MISSES); }
branch-instructions|branches			{ return sym(yyscanner, PERF_TYPE_HARDWARE, PERF_COUNT_HW_BRANCH_INSTRUCTIONS); }
branch-misses					{ return sym(yyscanner, PERF_TYPE_HARDWARE, PERF_COUNT_HW_BRANCH_MISSES); }
bus-cycles					{ return sym(yyscanner, PERF_TYPE_HARDWARE, PERF_COUNT_HW_BUS_CYCLES); }
cpu-clock					{ return sym(yyscanner, PERF_TYPE_SOFTWARE, PERF_COUNT_SW_CPU_CLOCK); }
task-clock					{ return sym(yyscanner, PERF_TYPE_SOFTWARE, PERF_COUNT_SW_TASK_CLOCK); }
page-faults|faults				{ return sym(yyscanner, PERF_TYPE_SOFTWARE, PERF_COUNT_SW_PAGE_FAULTS); }
minor-faults					{ return sym(yyscanner, PERF_TYPE_SOFTWARE, PERF_COUNT_SW_PAGE_FAULTS_MIN); }
major-faults					{ return sym(yyscanner, PERF_TYPE_SOFTWARE, PERF_COUNT_SW_PAGE_FAULTS_MAJ); }
context-switches|cs				{ return sym(yyscanner, PERF_TYPE_SOFTWARE, PERF_COUNT_SW_CONTEXT_SWITCHES); }
cpu-migrations|migrations			{ return sym(yyscanner, PERF_TYPE_SOFTWARE, PERF_COUNT_SW_CPU_MIGRATIONS); }
alignment-faults				{ return sym(yyscanner, PERF_TYPE_SOFTWARE, PERF_COUNT_SW_ALIGNMENT_FAULTS); }
emulation-faults				{ return sym(yyscanner, PERF_TYPE_SOFTWARE, PERF_COUNT_SW_EMULATION_FAULTS); }

L1-dcache|l1-d|l1d|L1-data		|
L1-icache|l1-i|l1i|L1-instruction	|
LLC|L2					|
dTLB|d-tlb|Data-TLB			|
iTLB|i-tlb|Instruction-TLB		|
branch|branches|bpu|btb|bpc		|
node					{ return str(yyscanner, PE_NAME_CACHE_TYPE); }

load|loads|read				|
store|stores|write			|
prefetch|prefetches			|
speculative-read|speculative-load	|
refs|Reference|ops|access		|
misses|miss				{ return str(yyscanner, PE_NAME_CACHE_OP_RESULT); }

<config>{
config			{ return term(yyscanner, PARSE_EVENTS__TERM_TYPE_CONFIG); }
config1			{ return term(yyscanner, PARSE_EVENTS__TERM_TYPE_CONFIG1); }
config2			{ return term(yyscanner, PARSE_EVENTS__TERM_TYPE_CONFIG2); }
name			{ return term(yyscanner, PARSE_EVENTS__TERM_TYPE_NAME); }
period			{ return term(yyscanner, PARSE_EVENTS__TERM_TYPE_SAMPLE_PERIOD); }
branch_type		{ return term(yyscanner, PARSE_EVENTS__TERM_TYPE_BRANCH_SAMPLE_TYPE); }
,			{ return ','; }
"/"			{ BEGIN(INITIAL); return '/'; }
}

mem:			{ BEGIN(mem); return PE_PREFIX_MEM; }
r{num_raw_hex}		{ return raw(yyscanner); }
{num_dec}		{ return value(yyscanner, 10); }
{num_hex}		{ return value(yyscanner, 16); }

{modifier_event}	{ return str(yyscanner, PE_MODIFIER_EVENT); }
{name}			{ return str(yyscanner, PE_NAME); }
"/"			{ BEGIN(config); return '/'; }
-			{ return '-'; }
,			{ BEGIN(event); return ','; }
:			{ return ':'; }
"{"			{ BEGIN(event); return '{'; }
"}"			{ return '}'; }
=			{ return '='; }
\n			{ }

<mem>{
{modifier_bp}		{ return str(yyscanner, PE_MODIFIER_BP); }
:			{ return ':'; }
{num_dec}		{ return value(yyscanner, 10); }
{num_hex}		{ return value(yyscanner, 16); }
	/*
	 * We need to separate 'mem:' scanner part, in order to get specific
	 * modifier bits parsed out. Otherwise we would need to handle PE_NAME
	 * and we'd need to parse it manually. During the escape from <mem>
	 * state we need to put the escaping char back, so we dont miss it.
	 */
.			{ unput(*yytext); BEGIN(INITIAL); }
	/*
	 * We destroy the scanner after reaching EOF,
	 * but anyway just to be sure get back to INIT state.
	 */
<<EOF>>			{ BEGIN(INITIAL); }
}

%%

int parse_events_wrap(void *scanner __used)
{
	return 1;
}
