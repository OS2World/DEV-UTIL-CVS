/*
** $Id: cvs2log.cmd,v 1.1.3.1.4.4 2006/03/05 08:04:31 andrew_belov Exp $
**
** CVS to ChangeLog generator.
**
** Generate a change log prefix from a CVS repository and the
** ChangeLog (if any). The new prefix is prepended to the ChangeLog.
** The editor specified by the CVSEDITOR environment variable (or a
** default editor, if CVSEDITOR is not set) is invoked with the new
** ChangeLog as an argument.
**
** The files %HOME%\.cvsauthors and/or %ETC%\.cvsauthors contain a
** list of all known login names and their corresponding full names
** and email addresses.
**
** Usage: cvs2log [-?Rgv] [-c changelog] [-d date] [-i indent]
**   [-l length] [-t tabwidth] [-A authors] [files...]
**
** Options:
**  -?            Display usage information.
**  -R            Process directories recursively.
**  -c changelog  Specify a different name for the ChangeLog
**                (default 'ChangeLog').
**  -g            Use a 'global' changelog, as opposed to a ChangeLog
**                local to each directory.
**  -d date       Specify a date argument to 'cvs log'.
**  -i indent     Indent ChangeLog lines by 'indent' spaces (default 8).
**  -l length     Try to limit log lines to 'length' characters
**                (default 79).
**  -t tabwidth   Tab stops are every 'tabwidth' characters (default 8).
**  -v            Append RCS revision to file names in log lines.
**  -a authors    Specify a different path for '.cvsauthors'.
**
** 'files...' can be any combination of files (including wildcards) and
** (CVS controlled) directories.
**
** Log entries that start with '#' are ignored.
** Log entries that start with '{topic}', where 'topic' contains
** neither white space nor '}', are clumped together.
**
** Based on rcs2log.sh by Paul Eggert <eggert@twinsun.com>.
**
** Copyright (C) 1998  Andreas Huber <ahuber@ping.at>
**
** This program is free software; you can redistribute it and/or
** modify it under the terms of the GNU General Public License
** as published by the Free Software Foundation; either version 2
** of the License, or (at your option) any later version.
**
** This program is distributed in the hope that it will be useful,
** but WITHOUT ANY WARRANTY; without even the implied warranty of
** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
** GNU General Public License for more details.
**
** You should have received a copy of the GNU General Public License
** along with this program; see the file COPYING. If not, write to
** the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
** Boston, MA 02111-1307, USA.
*/
call RxFuncAdd 'SysLoadFuncs', 'RexxUtil', 'SysLoadFuncs'
call SysLoadFuncs

/*
** Constants.
**/
EXIT_SUCCESS		= 0
EXIT_FAILURE		= 1
EXIT_USAGE			= 2
EXIT_SIGNAL			= 3

FALSE				= 0
TRUE				= \FALSE

MONTHS				= 'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'

SOH					= d2c(1)
TAB					= d2c(9)

CVSEDITOR_DEFAULT	= 'tedit'

/*
** Configurable options.
*/
recursive			= FALSE
datearg				= ''
global_changelog	= FALSE
changelog_name		= 'ChangeLog'
changelog_prefix	= 'ChangeLog.new'
line_length			= 79
line_indent			= 8
tabwidth			= 8
cvsauthors			= ''
revision			= FALSE
cvseditor			= ''

/*
** Global names known to all procedures.
*/
globals = 'EXIT_SUCCESS EXIT_USAGE EXIT_FAILURE EXIT_SIGNAL',
	' FALSE TRUE argc argv. MONTHS SOH TAB',
	'recursive datearg global_changelog changelog_name changelog_prefix',
	'line_length line_indent tabwidth cvsauthors revision cvseditor',
	'fullname. mailaddr.'

/*
** Main body.
*/
main:
	argc = 1; argv. = ''; argv.0 = 'cvs2log'
	signal on halt name signal_handler
	do i = 1 to arg(); call setargv arg(i); end
	optind = 0
	options = '?Rc::d::gi::l::t::va::'
	do forever
		c = getopt(options)
		if c <= 0 then leave
		select
			when c = '?' | c = ':' then call usage
			when c = 'R' then recursive = TRUE
			when c = 'c' then changelog_name = optarg
			when c = 'g' then global_changelog = TRUE
			when c = 'd' then datearg = ' "-d'||optarg||'"'
			when c = 'i' then line_indent = numeric_argument(1, 100)
			when c = 'l' then line_length = numeric_argument(40, 200)
			when c = 't' then tabwidth = numeric_argument(0, 100)
			when c = 'v' then revision = TRUE
			when c = 'a' then cvsauthors = optarg
			otherwise exit EXIT_FAILURE
		end
	end
	files = ''
	do while optind < argc
		path = translate(argv.optind, '/', '\')
		i = lastpos('/', path)
		if i < length(path) then if is_directory(path) then do
			path = path||'/'
			i = length(path)
		end
		dir = substr(path, 1, i)
		if dir = '' then
			dir = './'
		filename = substr(argv.optind, i+1)
		if filename = '' then
			filename = '*'
		if wordpos(dir, files) = 0 then do
			files = files dir
			files.dir = ''
		end
		if filename = '*' then
			files.dir = filename
		else if files.dir \= '*' then
			files.dir = files.dir filename
		optind = optind+1
	end
	cvseditor = value('CVSEDITOR',, 'OS2ENVIRONMENT')
	if cvseditor = '' then cvseditor = CVSEDITOR_DEFAULT
	call read_authors
	repository = ''
	if global_changelog then do
		call parse_changelog './'
		repository = get_repository('./')
		text. = ''; text.0 = 0
	end
	if files = '' then
		call do_directory './', '*', repository
	else do
		do i = 1 to words(files)
			dir = word(files, i)
			call do_directory dir, files.dir, repository
		end
	end
	if global_changelog then do
		call sort_log
		call format_log './'
		call edit_changelog './'
	end
	exit EXIT_SUCCESS

edit_changelog: procedure expose (globals)
	parse arg dir
	dir = translate(dir, '\', '/')
	if exists(dir||changelog_prefix) then do
		tempname = SysTempFileName(dir||changelog_name||'.?????')
		'@copy' dir||changelog_prefix '+' dir||changelog_name,
			tempname '>nul 2>&1'
		'@erase' dir||changelog_name dir||changelog_prefix '>nul 2>&1'
		'@rename' tempname changelog_name '>nul 2>&1'
		'@'||cvseditor dir||changelog_name
	end
	return

parse_timestamp: procedure expose (globals)
	parse arg line
	if verify(line, ' '||TAB) > 1 then return ''
	parse var line year '-' month '-' day .
	if year \= '' & month \= '' & day \= '' then
		return ' "-d>'||year||'-'||month||'-'||day||'"'
	parse var line . ' ' month ' ' day ' ' . ':' . ':' . ' ' year .
	if year \= '' & month \= '' & day \= '' then do
		month = wordpos(month, MONTHS)
		return ' "-d>'||year||'-'||month||'-'||day||'"'
	end
	parse var line day ' ' month ' ' year .
	if year \= '' & month \= '' & day \= '' then do
		month = wordpos(month, MONTHS)
		return ' "-d>'||year||'-'||month||'-'||day||'"'
	end
	parse var line . ', ' day ' ' month ' ' year .
	if year \= '' & month \= '' & day \= '' then do
		month = wordpos(month, MONTHS)
		return ' "-d>'||year||'-'||month||'-'||day||'"'
	end
	return ''

parse_changelog: procedure expose (globals) tz dateval
	parse arg dir
	dateval = datearg
	filename = dir||changelog_name
	if stream(filename, 'c', 'query size') = 0 then
		return FALSE
	call stream filename, 'c', 'open read'
	do while lines(filename) > 0
		line = translate(linein(filename), ' ', TAB)
		if dateval = '' then dateval = parse_timestamp(line)
		line = space(line, 0)
		parse var line '#change-log-time-zone-rule:' tz
		if tz \= '' then leave
	end
	call stream filename, 'c', 'close'
	if tz = '' then
		tz = value('TZ',, 'OS2ENVIRONMENT')
	return TRUE

exists: procedure expose (globals)
	parse arg filename
	return stream(filename, 'c', 'query size') \= ''

is_directory: procedure expose (globals)
	parse arg path
	if pos('?', path) > 0 | pos('*', path) > 0 then
		return false
	filespec = translate(path, '\', '/')
	if SysFileTree(filespec, filelist, 'do', '*+-*-') \= 0 then
		call die '"'||path||'": Not enough memory'
	return filelist.0 > 0

do_directory: procedure expose (globals) dateval tz text.
	parse arg dir, filelist, repository
        call do_files dir, filelist, repository
	if filelist = '*' & recursive then do
		call read_entries dir
		do i = 1 to entries.0
                        pdir = dir||entries.i||'/'
                        say "Interim: " || pdir
                        call do_directory pdir, '*', repository
		end
	end
	return

do_files: procedure expose (globals) dateval tz text.
	parse arg dir, filelist, repository
	if \global_changelog then do
		call parse_changelog dir
		repository = get_repository(dir)
		text. = ''; text.0 = 0
	end
	call parse_log dir, filelist, repository
	if \global_changelog then do
		call sort_log
		call format_log dir
		call edit_changelog dir
	end
	return

format_log: procedure expose (globals) tz text.
	parse arg dir
	changelog = dir||changelog_prefix
	if stream(changelog, 'c', 'open write') \= 'READY:' then
		call die 'Cannot write to' changelog '.'
	indent_string = ''
	i = line_indent
	if tabwidth > 0 then do while i >= tabwidth
		indent_string = indent_string||TAB
		i = i-tabwidth
	end
	do i; indent_string = indent_string||' '; end
	hostname = get_hostname()
	date = ''; time = ''; author = ''; log = ''
	clumpname = ''; files = ''; filesknown. = FALSE
	do i = 1 to text.0
		parse var text.i nfilename nrev ndate ntime text.i
		if left(text.i, 1) = '+' | left(text.i, 1) = '-' then
			parse var text.i ntz nauthor (SOH) text.i
		else
			parse var text.i nauthor (SOH) nlog
		
		nclumpname = ''
		if left(nlog, 1) = '{' then do
			p = verify(nlog, ' }'||TAB||SOH, 'm')
			if substr(nlog, p, 1) = '}' then do
				nclumpname = substr(nlog, 2, p-2)
				nlog = substr(nlog,,
					p+verify(substr(nlog, p+1), ' '||TAB))
			end
		end
		if log \= nlog | date \= ndate | author \= nauthor then do
			if date \= '' then do
				call print_log changelog, files, log
				if nclumpname = '' | nclumpname \= clumpname then
					call lineout changelog, ''
			end
			clumpname = nclumpname
			log = nlog
			files = ''; filesknown. = FALSE
		end
		if date \= ndate | author \= nauthor then do
			date = ndate; time = ntime; author = nauthor
			zone = ''
			if tz \= '' then do
				p = pos('-', time)
				if p = 0 then p = pos('+', time)
				if p > 0 then zone = substr(time, p)
			end
			if fullname.author \= '' then
				fullname = fullname.author
			else
				fullname = author
			call charout changelog, date||zone||'  '||fullname
			if mailaddr.author \= '' then
				mailaddr = mailaddr.author
			else
				mailaddr = author||'@'||hostname
			call lineout changelog, '  <'||mailaddr||'>'
			call lineout changelog, ''
		end
		if \filesknown.nfilename then do
			filesknown.nfilename = TRUE
			if files = '' then
				files = ' '||nfilename
			else
				files = files||', '||nfilename
			if revision & nrev \= '?' then
				files = files||' '||nrev
		end
	end
	if date \= '' then do
		call print_log changelog, files, log
		call lineout changelog, ''
	end
	call stream changelog, 'c', 'close'
	if stream(changelog, 'c', 'query size') = 0 then
		call SysFileDelete translate(changelog, '\', '/')
	return

print_log: procedure expose (globals) indent_string
	parse arg changelog, files, log
	do forever
		c = left(log, 1)
		if c \= '(' & c \= '[' then leave
		c = translate(c, ')]', '([')
		i = verify(log, SOH||c, 'm')
		if substr(log, i, 1) \= c then leave
		files = files substr(log, 1, i)
		log = substr(log, i+verify(substr(log, i+1), ' '||TAB))
	end
	call charout changelog, indent_string||'*'||files||':'
	indent = ' '
	if line_indent+1+length(files)+2+pos(SOH, log) >= line_length then do
		call lineout changelog, ''
		indent = indent_string
	end
	do forever
		i = pos(SOH, log)
		if i = 0 then leave
		logline = substr(log, 1, i-1)
		if space(translate(logline, ' ', TAB), 0) = '' then
			call lineout changelog, ''
		else
			call lineout changelog, indent||logline
		log = substr(log, i+1)
		indent = indent_string
	end
	return

read_entries: procedure expose (globals) entries.
	parse arg dir
	filename = dir||'CVS/Entries'
	if stream(filename, 'c', 'open read') \= 'READY:' then
		call die '"'||dir||'" is not a CVS controlled directory.'
	entries. = ''; entries.0 = 0
	do while lines(filename) > 0
		line = linein(filename)
		parse var line 'D/' dir '/'
		if dir \= '' then do
                        i = entries.0+1
                        entries.i = dir
			entries.0 = i
		end
	end
	call stream filename, 'c', 'close'
	return

parse_log: procedure expose (globals) dateval text.
	parse arg dir, filelist, repository
	files = ''; author. = FALSE
	do i = 1 to words(filelist)
		file = word(filelist, i)
		if file = '*' then
			file = left(dir, length(dir)-1)
		else
			file = dir||file
		if length(files)+length(file) > 1000 then do
			call parse_log_partial files, repository
			files = ''
		end
		files = files file
	end
	if files \= '' then
		call parse_log_partial files, repository
	return

parse_log_partial: procedure expose (globals) dateval text.
	parse arg files, repository
	queue = rxqueue('create')
	call rxqueue 'set', queue
	'@cvs -Qn log -l'||dateval||files||' | rxqueue '||queue
	state = 0
	do while queued() > 0
		line = linein('queue:')
		if state = 0 then do
			if pos('RCS file:', line) = 1 then do
				parse var line . ': ' filename
				if abbrev(filename, repository||'/') then
					filename = substr(filename, length(repository)+2)
				if right(filename, 2) = ',v' then
					filename = left(filename, length(filename)-2)
				i = lastpos('Attic/', filename)
				if i > 0 then
					filename = delstr(filename, i, 6)
				if right(filename, length(changelog_name)) \=,
						changelog_name then do
					rev = '?'
					state = 1
				end
			end
		end
		else if pos('==========', line) = 1 then do
			if state = 2 then call push_text text
			state = 0
		end
		else if state = 1 then do
			if pos('revision ', line) = 1 then do
				parse var line . ' ' rev ' ' .
				state = 2
			end
		end
		else if state = 2 then do
			if pos('----------', line) = 1 then do
				call push_text text
				state = 1
				iterate
			end
			if pos('date: ', line) = 1 then do
				parse var line . ': ' date ' ' time,
					';' . 'author: ' author ';'
				date = translate(date, '-', '/')
				text = filename rev date time author||SOH
				rev = '?'
				iterate
			end
			if pos('branches: ', line) = 1 then iterate
			if line = 'Initial revision' then
				line = 'New file.'
			else do
				parse var line 'file ' .,
					' was initially added on branch ' branch '.'
				if branch \= '' then
					line = 'New file.'
			end
			text = text||line||SOH
		end
	end
	call rxqueue 'delete', queue
	return

push_text: procedure expose text.
	parse arg text
	i = text.0+1
	text.i = text
	text.0 = i
	return

sort_log: procedure expose text.
	if text.0 > 1 then
		call quicksort 1, text.0
	return

quicksort: procedure expose text.
	parse arg l, r
	i = l; j = r; x = (l+r)%2; x = text.x
	do forever
		do while compare_log(text.i, x) < 0; i = i+1; end
		do while compare_log(x, text.j) < 0; j = j-1; end
		if i <= j then do
			w = text.i; text.i = text.j; text.j = w
			i = i+1; j = j-1
		end
		if i > j then leave
	end
	if l < j then call quicksort l, j
	if i < r then call quicksort i, r
	return

compare_log: procedure
	parse arg a, b
	parse var a filename1 rev1 date1 time1 author1 log1
	parse var b filename2 rev2 date2 time2 author2 log2
	select
		when date1 time1 << date2 time2 then return +1
		when date1 time1 >> date2 time2 then return -1
		otherwise nop
	end
	select
		when author1 << author2 then return -1
		when author1 >> author2 then return +1
		otherwise nop
	end
	select
		when log1 << log2 then return -1
		when log1 >> log2 then return +1
		otherwise nop
	end
	select
		when filename1 rev1 << filename2 rev2 then return -1
		when filename1 rev1 >> filename2 rev2 then return +1
		otherwise nop
	end
	return 0

is_absolute: procedure expose (globals)
	parse arg path
	return pos(':/', path) = 2 | pos('/', path) = 1

get_repository: procedure expose (globals)
	parse arg dir
	repository = linein(dir||'CVS/Repository')
	call stream dir||'CVS/Repository', 'c', 'close'
	cvsroot = linein(dir||'CVS/Root')
	call stream dir||'CVS/Root', 'c', 'close'
	if repository = '' || cvsroot = '' then
		call die 'This is not a CVS controlled directory.'
	if left(cvsroot, 1) = ':' then
		parse var cvsroot ':' method ':' cvsroot
	else if pos(cvsroot, ':') = 0 then
		method = 'local'
	else
		method = 'server'
	if method = 'local' then do
		if \is_absolute(repository) then
			repository = cvsroot||'/'||repository
		if \is_directory(repository) then
			call die repository||': Bad repository (see CVS/Repository).'
	end
	else
		parse var cvsroot . ':' cvsroot
	return repository

get_hostname: procedure expose (globals)
	hostname = value('HOSTNAME',, 'OS2ENVIRONMENT')
	if hostname \= '' then return hostname
	queue = rxqueue('create')
	call rxqueue 'set', queue
	'hostname | rxqueue '||queue
	if rc = 0 then if lines('queue:') > 0 then
		hostname = linein('queue:')
	call rxqueue 'delete', queue
	if hostname = '' then
		hostname = 'localhost'
	return hostname

find_authors: procedure expose (globals)
	parse arg env
	dir = value(env,, 'OS2ENVIRONMENT')
	if dir \= '' then if exists(dir||'/.cvsauthors') then
		return dir||'/.cvsauthors'
	return ''

read_authors: procedure expose (globals)
	fullname. = ''; mailaddr. = ''
	filename = cvsauthors
	if filename = '' then do
		filename = find_authors('HOME')
		if filename = '' then
			filename = find_authors('ETC')
		if filename = '' then
			return
	end
	if stream(filename, 'c', 'open read') \= 'READY:' then
		call die 'Cannot open' filename 'for reading.'
	do while lines(filename) > 0
		line = linein(filename)
		parse var line login '|' fullname '|' mailaddr
		if login \= '#' then do
			fullname.login = fullname
			mailaddr.login = mailaddr
		end
	end
	call stream filename, 'c', 'close'
	return

die: procedure expose (globals)
	parse arg text
	call lineout 'stderr:', argv.0||': '||text
	exit EXIT_FAILURE

usage: procedure expose (globals)
	say 'Usage: '||argv.0||' [-?Rgv] [-c changelog] [-d date] [-i indent]'
	say '  [-l length] [-t tabwidth] [-a authors] [files...]'
	exit EXIT_USAGE

numeric_argument: procedure expose (globals) optopt optarg
	parse arg minval, maxval
	if \datatype(optarg, 'w') then
		call die '-'||optopt optarg||': invalid argument.'
	if optarg < minval | optarg > maxval then
		call die '-'||optopt optarg||': argument out of range',
			'['||minval||', '||maxval||'].'
	return optarg

getopt: procedure expose (globals) optind optarg optopt optptr
	parse arg options
	if optind = 0 then optptr = 0
	if optptr = 0 | optptr > length(argv.optind) then do
		if optind >= argc then return -1
		optind = optind+1
		optptr = 1
		if substr(argv.optind, optptr, 1) \= '-' then return 0
		optptr = optptr+1
	end
	optopt = substr(argv.optind, optptr, 1)
	optptr = optptr+1
	if optopt = '-' then do
		optind = optind+1
		optptr = 0
		return -1
	end
	i = pos(optopt, options)
	if optopt = ':' | i = 0 then do
		say argv.0||': -'||optopt||' is not a valid option.'
		return '?'
	end
	if substr(options, i+1, 1) = ':' then do
		if optptr <= length(argv.optind) then do
			optarg = substr(argv.optind, optptr)
			optptr = 0
			return optopt;
		end
		if substr(options, i+2, 1) = ':' then do
			i = optind+1
			optptr = 1
			if i < argc & substr(argv.i, optptr, 1) \= '-' then do
				optind = i
				optarg = argv.optind
				optptr = 0
				return optopt
			end
			say argv.0||': -'||optopt||' is missing an argument.'
			return ':'
		end
		optptr = 0
	end
	optarg = ''
	return optopt

setargv: procedure expose (globals)
	parse arg args
	inquote = FALSE
	do forever
		parse var args arg args
		if arg = '' then leave
		quotes = FALSE
		i = 1
		do forever
			i = pos('"', arg, i)
			if i = 0 then leave
			if i > 1 then if substr(arg, i-1, 1) = '\' then do
				arg = delstr(arg, i-1, 1)
				iterate
			end
			arg = delstr(arg, i, 1)
			quotes = \quotes
		end
		if inquote then
			argv.argc = argv.argc arg
		else do
			argv.argc = arg
			argc = argc+1
		end
		if quotes then inquote = \inquote
	end
	return

signal_handler:
	call lineout 'stderr:', argv.0||': terminated by SIGINT.'
	exit EXIT_SIGNAL

