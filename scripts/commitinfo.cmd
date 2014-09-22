/*
** $Id: commitinfo.cmd,v 1.1.3.1 1999/06/17 15:20:45 root Exp $
**
** Rexx filter to handle pre-commit checking of files. This program
** records the last directory where commits will be taking place for
** use by the loginfo script. For new files, it optionally forces the
** existence of an RCS "Id" keyword in the first ten lines of the file.
** For existing files, it checks the version number on the "Id" line
** to prevent losing changes because an old version of a file was
** copied into the directory.
**
** It also performs access control for matching repository names.
**
** Possible future enhancements:
**
**  Check for cruft left by unresolved conflicts. Search for
**  "^<<<<<<<$", "^-------$", and "^>>>>>>>$".
**
** Original perl version by David Hampton <hampton@cisco.com>
** and 'hacked on lots' by Greg A. Woods <woods@web.net>.
**
** Access control lists originally by David G. Grubbs <dgg@ksr.com>.
**
** Usage: commitinfo [-?lrcdA] repository files...
**
** Options:
**  -?  Display usage information.
**  -r  Record this directory as the last one checked.
**  -c  Check the "Id" keyword.
**  -l  Check for existence of a "Log" keyword (not implemented).
**  -d  Enable debugging (not implemented).
**  -A  Perform access control.
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
*/
EXIT_SUCCESS	= 0
EXIT_FAILURE	= 1
EXIT_USAGE		= 2
EXIT_SIGNAL		= 3

FALSE			= 0
TRUE			= \FALSE

TAB				= d2c(9)

TEMP_DIR		= value('TMPDIR',, 'OS2ENVIRONMENT')
LAST_FILE		= TEMP_DIR||'/#cvs.files.lastdir'

CVSROOT			= get_repository()

AVAIL_FILE		= CVSROOT||'/CVSROOT/avail'

ENTRIES			= 'CVS/Entries'

no_log			=,
'%s - Contains an RCS $'||Log||'$ keyword.  It must not!\n'

no_id			=,
'%s - Does not contain a properly formatted line with the keyword "Id:".\n',
'       Please see the template files for an example.\n'

no_name			=,
'%s - The ID line should contain only "$'||'Id'||'$"\n',
'       for a newly created file.\n'

bad_name		=,
"%s - The file name '%s' in the ID line does not match\n",
"       the actual filename.\n"

bad_version		=,
"%s - How dare you!!!  You replaced your copy of the file '%s'\n",
"       which was based upon version '%s', with an %s version based\n",
"       upon %s.  Please move your '%s' out of the way, perform an\n",
"       update to get the current version, and then merge your changes\n",
"       into that file, then try the commit again.\n"

/*
** Configurable options.
*/
debug				= FALSE

/*
** Check each file (except dot files) for an RCS "Log" keyword.
*/
check_log			= FALSE

/*
** Check each file (except dot files) for an RCS "Id" keyword.
*/
check_id			= FALSE

/*
** Record the directory for later use by the loginfo script.
*/
record_directory	= FALSE

/*
** Check if user has commit privilege.
*/
access_control		= FALSE

/*
** Global names known to all procedures.
*/
globals = 'EXIT_SUCCESS EXIT_FAILURE EXIT_USAGE EXIT_SIGNAL',
	'FALSE TRUE TAB argv. argc',
	'TEMP_DIR LAST_FILE AVAIL_FILE ENTRIES CVSROOT',
	'no_log no_id no_name bad_name bad_version',
	'debug check_log check_id record_directory'

/*
** Main body.
*/
main:
	argc = 1; argv. = ''; argv.0 = 'commitinfo'
	signal on halt name signal_handler
	do i = 1 to arg(); call setargv arg(i); end
	options = '?rcldA'
	optind = 0
	do forever
		c = getopt(options)
		if c <= 0 then leave
		select
			when c = '?' | c = ':' then call usage
			when c = 'r' then record_directory = TRUE
			when c = 'c' then check_id = TRUE
			when c = 'l' then check_log = TRUE
			when c = 'd' then debug = TRUE
			when c = 'A' then access_control = TRUE
			otherwise exit EXIT_FAILURE
		end
	end
	if optind+2 > argc then call usage
	id = SysGetPPid()
	if access_control then if \check_access() then
		exit EXIT_FAILURE
	dir = argv.optind; optind = optind+1
/*
** Now check each file name passed in, except for dot files. Dot files
** are considered to be administrative file by this script.
*/
	if check_id then do
		call read_entries
		failed = 0
		do while optind < argc
			file = argv.optind
			optind = optind+1
			if pos(file, '.') = 1 then iterate
			failed = failed+check_version(file)
		end
		if failed > 0 then do
			call lineout ''
			exit EXIT_FAILURE
		end
	end
/*
** Record this directory as the last one checked. This will be used
** by the loginfo script to determine when it is processing the final
** directory of a multi-directory commit.
*/
	if record_directory then
		call write_line LAST_FILE||'.'||id, dir
	exit EXIT_SUCCESS

/*
** Subroutines.
*/
/*
** CVS passes to argv. an absolute directory pathname (the repository
** appended to your %CVSROOT% environment variable), followed by a list
** of filenames within that directory.
**
** We walk through the avail file looking for a line that matches both
** the username and repository.
**
** A username match is simply the user's name appearing in the second
** column of the avail line in a space-or-comma separate list.
**
** A repository match is either:
**  - One element of the third column matches argv.1, or some
**    parent directory of argv.1.
**  - Otherwise *all* file arguments (argv.2..argv.(argc-1)) must
**    be in the file list in one avail line.
**  - In other words, using directory names in the third column of
**    the avail file allows committing of any file (or group of
**    files in a single commit) in the tree below that directory.
**  - If individual file names are used in the third column of
**    the avail file, then files must be committed individually or
**    all files specified in a single commit must all appear in
**    third column of a single avail line.
*/
check_access: procedure expose (globals) optind
	user_name = value('LOGNAME',, 'OS2ENVIRONMENT')
	if user_name = '' then
		user_name = value('USER',, 'OS2ENVIRONMENT')
	if stream(AVAIL_FILE, 'c', 'open read') \= 'READY:' then
		exit EXIT_SUCCESS
	parse var argv.optind (CVSROOT) '/' dir
	if dir = '' then dir = argv.optind
	access_granted = TRUE
	universal_off = FALSE
	do while lines(AVAIL_FILE) > 0
		line = space(translate(linein(AVAIL_FILE), '  ', ','||TAB))
		if line = ' ' | left(line, 1) = '#' then iterate
		parse var line avail '|' user_list '|' file_list
		if abbrev('available', avail) then
			avail = TRUE
		else if abbrev('unavailable', avail) then
			avail = FALSE
		else do
			say 'Bad avail line:' line
			iterate
		end
		if \avail & user_list = '' & file_list = '' then
			universal_off = TRUE
		in_user = user_list = '' | wordpos(user_name, user_list) > 0
		in_repo = file_list = ''
		if \in_repo then do
			do i = 1 to words(file_list) while \in_repo
				file = word(file_list, i)
				in_repo = dir = file | abbrev(dir, file);
			end
			if \in_repo then do
				in_repo = TRUE;
				do i = optind to argc-1 while in_repo
					file = dir||'/'||argv.i
					in_repo = wordpos(file, file_list) > 0
				end
			end
		end
		if in_user & in_repo then
			access_granted = avail
	end
	call stream AVAIL_FILE, 'c', 'close'
	if \access_granted then do
		say '**** Access denied: Insufficient Karma ('||user_name||,
			'|'||dir||').'
	end
	else if universal_off then
		say '**** Access granted: Personal Karma exceeds Environmental',
			'Karma.'
	return access_granted

/*
** Suck in the Entries file.
*/
read_entries: procedure expose (globals) cvsversion.
	if stream(ENTRIES, 'c', 'open read') \= 'READY:' then
		call die 'Cannot open' ENTRIES 'for reading.'
	cvsversion. = ''
	do while lines(ENTRIES) > 0
		parse value linein(ENTRIES) with,
			. '/' filename '/' version '/'
		cvsversion.filename = version
	end
	call stream ENTRIES, 'c', 'close'
	return

check_version: procedure expose (globals) cvsversion.
	parse arg filename
	if stream(filename, 'c', 'open read') \= 'READY:' then
		call die 'Cannot open' filename 'for reading.'
	pos = 0
	do i = 1 to 10 while lines(filename) > 0
		parse value linein(filename) with line
		pos = pos('$Id', line)
		if pos > 0 then leave
	end
	if pos = 0 then do
		call printf no_id, filename
		return 1
	end
	parse value substr(line, pos) with '$' id rname version . '$'
	if cvsversion.filename = '0' then do
		if rname \= '' then do
			call printf no_name, filename
			return 1
		end
		return 0
	end
	if rname \= filename||',v' then do
		call printf bad_name, filename, left(rname, length(rname)-2)
		return 1
	end
	i = compare_versions(cvsversion.filename, version)
	if i < 0 then do
		call printf bad_version, filename, filename,,
			cvsversion.filename, 'newer', version, filename
		return 1
	end
	if i > 0 then do
		call printf bad_version, filename, filename,,
			cvsversion.filename, 'older', version, filename
		return 1
	end
	return 0

compare_versions: procedure
	parse arg a, b
	do forever
		parse var a i '.' a
		parse var b j '.' b
		if i \= j then leave
	end
	if i < j then
		return -1
	else if i > j then
		return +1
	return 0

write_line: procedure expose (globals)
	parse arg filename, line
	call SysFileDelete translate(filename, '\', '/')
	if stream(filename, 'c', 'open write') \= 'READY:' then
		die 'Cannot open' filename 'for writing.'
	call lineout filename, line
	call stream filename, 'c', 'close'
	return

printf: procedure
    format = arg(1)
    i = 1
    do while format \= ''
        p = verify(format, '%\', 'm')
        if p = 0 then do
            call charout 'stderr:', format
            leave
        end
        if substr(format, p, 2) = '%s' then do
            call charout 'stderr:', left(format, p-1)
            i = i+1
            call charout 'stderr:', arg(i)
        end
        else if substr(format, p, 2) = '\n' then
            call lineout 'stderr:', left(format, p-1)
		else
			call charout 'stderr:', left(format, p+1)
        format = substr(format, p+2)
    end
    return

get_repository: procedure
	cvsroot = value('CVSROOT',, 'OS2ENVIRONMENT')
	if left(cvsroot, 1) = ':' then
		parse var cvsroot ':' method ':' cvsroot
	else if pos(cvsroot, ':') = 0 then
		method = 'local'
	else
		method = 'server'
	if method \= 'local' then
		parse var cvsroot . ':' cvsroot
	return cvsroot

usage: procedure expose (globals)
	say 'Usage: '||argv.0||' [-?lrcdA] repository files...'
	exit EXIT_USAGE

die: procedure expose (globals)
	parse arg text
	call lineout 'stderr:', argv.0||': '||text
	exit EXIT_FAILURE

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
	call lineout 'stderr:', argv.0||': interrupted by SIGINT.'
	exit EXIT_SIGNAL

