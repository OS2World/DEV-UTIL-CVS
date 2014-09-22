/*
** $Id: loginfo.cmd,v 1.1.3.1 1999/06/17 15:20:46 root Exp $
**
** Rexx filter to handle the log messages from the checkin of files in
** a directory. This script will group the lists of files by log message,
** and mail a single consolidated log message at the end of the commit.
**
** This file assumes a pre-commit checking program that leaves the names
** of the first and last commit directories in a temporary file.
**
** Commit messages are sent to the email addresses listed in the
** %CVSROOT%\maildist file on a per directory basis. This file also lists
** the names of files within %CVSROOT%\commitlogs to save commit messages
** to.
**
** The file %HOME%\.cvsauthors or %ETC%\.cvsauthors contains a list of
** all known login names and their corresponding full names and email
** addresses. This information is used determine the 'From:' address for
** commit messages.
**
** Usage: loginfo [-?dbS] [-i infolevel] [-a authors] repository files...
**
** Options:
**  -?            Display usage information.
**  -i infolevel  Include RCS ID and delta info:
**                 0: never,
**                 1: in mail only,
**                 2: in mail and logs (default).
**  -d            Enable debugging.
**  -b            Backup commitlogs on a monthly basis (requires gzip).
**  -a authors    Specify a different path for '.cvsauthors'.
**  -S            Do *not* include change summary.
**
** Originally by David Hampton <hampton@cisco.com>.
**
** Extensively hacked for FreeBSD by Peter Wemm <peter@dialix.com.au>,
** with parts stolen from Greg A. Woods' <woods@most.wierd.com> version.
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
EXIT_SIGNAL		= 3

FALSE			= 0
TRUE			= \FALSE

TAB				= d2c(9)

STATE_NONE		= 0
STATE_CHANGED	= 1
STATE_ADDED		= 2
STATE_REMOVED	= 3
STATE_LOG		= 4

TEMP_DIR		= value('TMPDIR',, 'OS2ENVIRONMENT')

FILE_PREFIX		= '#cvs.files'
LAST_FILE		= TEMP_DIR||'/'||FILE_PREFIX||'.lastdir'
CHANGED_FILE	= TEMP_DIR||'/'||FILE_PREFIX||'.changed'
ADDED_FILE		= TEMP_DIR||'/'||FILE_PREFIX||'.added'
REMOVED_FILE	= TEMP_DIR||'/'||FILE_PREFIX||'.removed'
LOG_FILE		= TEMP_DIR||'/'||FILE_PREFIX||'.log'
SUMMARY_FILE	= TEMP_DIR||'/'||FILE_PREFIX||'.summary'
MAIL_FILE		= TEMP_DIR||'/'||FILE_PREFIX||'.mail'
SUBJ_FILE		= TEMP_DIR||'/'||FILE_PREFIX||'.subj'

CVSROOT			= get_repository()

/*
** Configurable options.
**
** Where do you want the RCS ID and delta info?
** 0 = none,
** 1 = in mail only,
** 2 = RCS IDs in both mail and logs.
*/
rcsidinfo		= 2

/*
** Debug level, 0 = off.
*/
debug			= 0

/*
** Backup commit logs in %CVSROOT%\CVSROOT\commitlogs\ on a monthly
** basis (requires gzip).
*/
backup			= FALSE

/*
** Look for full names and email addresses in this file. The default
** is %ETC%\.cvsauthors or %HOME%\.cvsauthors.
*/
cvsauthors		= ''

/*
** Include a change summary with the commit message.
*/
include_summary	= TRUE

/*
** Global names known to all procedures.
*/
globals = 'EXIT_SUCCESS EXIT_FAILURE EXIT_SIGNAL',
	'FALSE TRUE argc argv. TAB',
	'STATE_NONE STATE_CHANGED STATE_ADDED STATE_REMOVED STATE_LOG',
	'TEMP_DIR FILE_PREFIX LAST_FILE CHANGED_FILE ADDED_FILE',
	'REMOVED_FILE LOG_FILE SUMMARY_FILE MAIL_FILE SUBJ_FILE',
	'CVSROOT rcsidinfo debug backup cvsauthors id'

/*
** Main body.
*/
main:
/*
** Initialize basic variables.
*/
	argc = 1; argv. = ''; argv.0 = 'loginfo'
	signal on halt name signal_handler
	do i = 1 to arg(); call setargv arg(i); end
	optind = 0
	options = '?id::ba::S'
	do forever
		c = getopt(options)
		if c <= 0 then leave
		select
			when c = '?' | c = ':' then call usage
			when c = 'i' then rcsidinfo = numeric_argument(0, 2)
			when c = 'd' then debug = TRUE
			when c = 'b' then backup = TRUE
			when c = 'a' then cvsauthors = optarg
			when c = 'S' then include_summary = FALSE
			otherwise exit EXIT_FAILURE
		end
	end
	id = SysGetPPid()
	state = STATE_NONE
	tag = ''
	login = value('LOGNAME',, 'OS2ENVIRONMENT')
	if login = '' then
		login = value('USER',, 'OS2ENVIRONMENT')
	path = argv.optind; optind = optind+1
	files = ''
	do while optind < argc
		files = concat(files, argv.optind, ' ')
		optind = optind+1
	end
	parse var path modulename '/' dir
	if dir = '' then dir = '.'
	dir = dir||'/'

	call append_line MAIL_FILE||'.'||id, read_maildist(path)
	call append_line SUBJ_FILE||'.'||id, path files
/*
** Check for a new directory first. This will always appear as a
** single item in the argument list, and an empty log message.
*/
	if pos('- New directory', files) = 1 then do
		header = build_header()
		text. = ''; text.0 = 0
		call push header
		call push ''
		call push '  '||path files
		call do_changes_file
		call mail_notification login
		call cleanup_tmpfiles
		exit EXIT_SUCCESS
	end
/*
** Check for an import command. This will always appear as a
** single item in the argument list, and a log message.
*/
	if pos('- Imported sources', files) = 1 then do
		header = build_header()
		text. = ''; text.0 = 0
		call push header
		call push ''
		call push '  '||path files
		call push ''
		call push '  Log:'
		i = text.0
		do while lines() > 0
			call push '  '||linein()
		end
		call compress_log i
		call do_changes_file
		call mail_notification login
		call cleanup_tmpfiles
		exit EXIT_SUCCESS
	end
/*
** Iterate over the body of the message collecting information.
*/
	tag = 'HEAD'
	call init_state STATE_CHANGED
	call init_state STATE_ADDED
	call init_state STATE_REMOVED
	text. = ''; text.0 = 0
	do while lines() > 0
		line = strip(translate(linein(), ' ', TAB), 't')
		if pos('Revision/Branch:', line) = 1 then do
			parse var line . ':' tag
			iterate
		end
		if word(line, 1) = 'Tag:' then do
			parse var line . ': ' tag
			iterate
		end
		if strip(line, 'l') = 'No tag' then do
			tag = 'HEAD'
			iterate
		end
		if pos('Modified Files', line) = 1 then do
			state = STATE_CHANGED
			iterate
		end
		if pos('Added Files', line) = 1 then do
			state = STATE_ADDED
			iterate
		end
		if pos('Removed Files', line) = 1 then do
			state = STATE_REMOVED
			iterate
		end
		if pos('Log Message', line) = 1 then do
			state = STATE_LOG
			iterate
		end
		if state = STATE_LOG then do
			temp = translate(line)
			if temp = 'PR:' |,
				temp = 'REVIEWED BY:' |,
				temp = 'SUBMITTED BY:' |,
				temp = 'OBTAINED FROM:' then iterate
			call push line
		end
		else if state \= STATE_NONE then
			call push_tag state, tag, line
	end
/*
** Skip leading and trailing blank lines from the log message. Also
** compress multiple blank lines in the body of the message down to a
** single blank line.
** (Note, this only does the mail and changes log, not the rcs log),
*/
	call compress_log
/*
** Find the log that matches this log message.
*/
	do i = 0
		if \exists(LOG_FILE||'.'||i||'.'||id) then leave
		call read_logfile LOG_FILE||'.'||i||'.'||id, ''
		if lines.0 = 0 then leave
		if compare_log() then leave
	end
/*
** Spit out the information gathered in this pass.
*/
	filename = ADDED_FILE||'.'||i||'.'||id
	call append_state_to_file filename, dir, STATE_ADDED

	filename = CHANGED_FILE||'.'||i||'.'||id
	call append_state_to_file filename, dir, STATE_CHANGED

	filename = REMOVED_FILE||'.'||i||'.'||id
	call append_state_to_file filename, dir, STATE_REMOVED

	call write_logfile LOG_FILE||'.'||i||'.'||id

	if rcsidinfo \= 0 & include_summary then do
		filename = SUMMARY_FILE||'.'||i||'.'||id
		tags = states.STATE_ADDED.keys
		do i = 1 to words(tags)
			call change_summary_added filename, word(tags, i)
		end
		tags = states.STATE_CHANGED.keys
		do i = 1 to words(tags)
			call change_summary_changed filename, word(tags, i)
		end
		tags = states.STATE_REMOVED.keys
		do i = 1 to words(tags)
			call change_summary_removed filename, word(tags, i)
		end
	end
/*
** Check wether this is the last directory. If not, quit.
*/
	if exists(LAST_FILE||'.'||id) then do
		line = read_line(LAST_FILE||'.'||id)
		if right(line, length(path)) \= path then do
			say 'More commits to come...'
			exit 0
		end
	end
/*
** This is it. The commits are all finished. Lump everthing together
** into a single message, fire a copy off to the mailing list, and drop
** it on the end of the Changes file.
*/
	header = build_header()
/*
** Produce the final compilation of the log messages.
*/
	text. = ''; text.0 = 0
	call push header
	call push ''
	do i = 0
		if \exists(LOG_FILE||'.'||i||'.'||id) then leave
		call read_logfile CHANGED_FILE||'.'||i||'.'||id, ''
		if lines.0 > 0 then
			call format_lists 'Modified'
		call read_logfile ADDED_FILE||'.'||i||'.'||id, ''
		if lines.0 > 0 then
			call format_lists 'Added'
		call read_logfile REMOVED_FILE||'.'||i||'.'||id, ''
		if lines.0 > 0 then
			call format_lists 'Removed'
		call read_logfile LOG_FILE||'.'||i||'.'||id, '  '
		if lines.0 > 0 then do
			call push '  Log:'
			call push_lines
		end
		if rcsidinfo = 2 & exists(SUMMARY_FILE||'.'||i||'.'||id) then do
			call push '  '
			call push '  Revision  Changes    Path'
			call read_logfile SUMMARY_FILE||'.'||i||'.'||id, '  '
			call push_lines
		end
		call push ''
	end
/*
** Put the log message at the beginning of the Changes file.
*/
	call do_changes_file
/*
** Now generate the extra info for the mail message.
*/
	if rcsidinfo = 1 then do
		revhdr = 0
		do i = 0
			if \exists(LOG_FILE||'.'||i||'.'||id) then leave
			if exists(SUMMARY_FILE||'.'||i||'.'||id) then do
				if revhdr = 0 then
					call push 'Revision  Changes    Path'
				call read_logfile SUMMARY_FILE||'.'||i||'.'||id, ''
				call push_lines
				revhdr = revhdr+1
			end
		end
		if revhdr > 0 then
			call push ''
	end
/*
** Mail out the notification.
*/
	call mail_notification login
	call cleanup_tmpfiles
	exit EXIT_SUCCESS
/*
** Subroutines.
*/
die: procedure expose (globals)
	parse arg text
	call lineout 'stderr:', argv.0||': '||text
	exit EXIT_FAILURE

push: procedure expose text.
	parse arg line
	i = text.0+1
	text.i = line
	text.0 = i
	return

/*
** Mail distribution and commit log mapping.
*/
read_maildist: procedure expose (globals)
	parse arg dir
	filename = CVSROOT||'/CVSROOT/maildist'
	if stream(filename, 'c', 'open read') \= 'READY:' then
		return ''
	default_dist = ''; all_dist = ''; mail_dist = ''
	do while lines(filename) > 0
		line = space(translate(linein(filename), '  ', ','||TAB))
		if left(line, 1) = '#' then iterate
		parse var line prefix dist
		if prefix = '' | dist = '' then iterate
		if prefix = 'DEFAULT' then
			default_dist = concat(default_dist, dist, ' ')
		else if prefix = 'ALL' then
			all_dist = concat(all_dist, dist, ' ')
		else if is_prefix(prefix, dir) then
			mail_dist = concat(mail_dist, dist, ' ')
	end
	call stream filename, 'c', 'close'
	if mail_dist = '' then
		mail_dist = concat(all_dist, default_dist, ' ')
	else
		mail_dist = concat(all_dist, mail_dist, ' ')
	return mail_dist

concat: procedure
	parse arg s1, s2, sep
	if s1 = '' then return s2
	if s2 = '' then return s1
	return s1||sep||s2

is_prefix: procedure expose (globals)
	parse arg prefix, dir
	if prefix = dir then return TRUE
	if length(prefix) >= length(dir) then return FALSE
	parse var dir (prefix) '/' dir
	return dir \= ''

append_line: procedure expose (globals)
	parse arg filename, line
	if stream(filename, 'c', 'open write') \= 'READY:' then
		call die 'Cannot open for append file '||filename||'.'
	call lineout filename, line
	call stream filename, 'c', 'close'
	return

build_header: procedure expose login
	date = insert('/', insert('/', date('s'), 4), 7)
	time = time('n')
	return left(login, 8)||'    '||date||' '||time

do_changes_file: procedure expose (globals) text.
	parse arg
	call read_logfile MAIL_FILE||'.'||id, ''
	unique. = FALSE
	do i = 1 to lines.0
		do j = 1 to words(lines.i)
			category = word(lines.i, j)
			if pos('@', category) > 0 then iterate
			if unique.category then iterate
			unique.category = TRUE
			changes = CVSROOT||'/CVSROOT/commitlogs/'||category
			if backup then
				call backup_changes changes
			call stream changes, 'c', 'open write'
			do k = 1 to text.0
				call lineout changes, text.k
			end
			call lineout changes, ''
			call stream changes, 'c', 'close'
		end
	end
	return

backup_changes: procedure expose (globals)
	parse arg filename
	parse value stream(filename, 'c', 'query datetime') with,
		m '-' . '-' y ' '
	if m \= '' & y \= '' then if m \= substr(date('s'), 5, 2) then do
		if y >= 70 then y = 1900+y; else y = 2000+y
		filename = translate(filename, '\', '/')
		'@rename' filename filename||'.'||y||'-'||m '>nul'
		if rc = 0 then
			'@gzip -q' filename||'.'||y||'-'||m '>nul'
		if rc \= 0 then
			call lineout 'stderr:', argv.0||': Warning:',
				'Couldn''t backup "'||filename||'".'
	end
	return

read_logfile: procedure expose lines.
	parse arg filename, leader
	lines. = ''; lines.0 = 0
	call stream filename, 'c', 'open read'
	i = 0
	do while lines(filename) > 0
		i = i+1
		lines.i = leader||linein(filename)
	end
	lines.0 = i
	call stream filename, 'c', 'close'
	return

cleanup_tmpfiles: procedure expose (globals)
	filemask = TEMP_DIR||'/'||FILE_PREFIX||'.*.'||id
	call SysFileTree translate(filemask, '\', '/'),,
		'files', 'FO', '*----'
	do i = 1 to files.0
		call SysFileDelete files.i
	end
	return

init_state: procedure expose states.
	parse arg state
	call value 'states.'||state||'.keys', ''
	return

init_tag: procedure expose states.
	parse arg state, tag
	call value 'states.'||state||'.'||tag||'.', ''
	call value 'states.'||state||'.'||tag||'.0', 0
	return

push_tag: procedure expose states.
	parse arg state, tag, line
	tags = value('states.'||state||'.keys')
	if wordpos(tag, tags) = 0 then do
		tags = tags||' '||tag
		call init_tag state, tag
		call value 'states.'||state||'.keys', tags
	end
	n = value('states.'||state||'.'||tag||'.0')
	do i = 1 to words(line)
		n = n+1
		call value 'states.'||state||'.'||tag||'.'||n, word(line, i)
	end
	call value 'states.'||state||'.'||tag||'.0', n
	return

exists: procedure
	parse arg filename
	return stream(filename, 'c', 'query size') \= ''

compare_log: procedure expose text. lines.
	if text.0 \= lines.0 then return 0
	do i = 1 to text.0
		if text.i \= lines.i then return 0
	end
	return 1

compress_log: procedure expose text.
	offset = 0
	if arg(1, 'e') then parse arg offset
	i = text.0
	do while i > offset & text.i = ''; i = i-1; end
	text.0 = i
	i = offset+1
	if left(text.i, 1) = '{' then do
		p = verify(text.i, ' }'||TAB, 'm')
		if substr(text.i, p, 1) = '}' then do
			text.i = substr(text.i,,
				p+verify(substr(text.i, p+1), ' '||TAB))
		end
	end
	do while i <= text.0 & text.i = ''; i = i+1; end
	j = offset
	do while i <= text.0
		j = j+1
		text.j = text.i
		if text.i \= '' then do; i = i+1; iterate; end
		i = i+1
		do while i <= text.0 & text.i = ''; i = i+1; end
	end
	text.0 = j
	return

append_state_to_file: procedure expose (globals) states.
	parse arg filename, dir, state
	tags = value('states.'||state||'.keys')
	do i = 1 to words(tags)
		call append_names_to_file filename, dir, word(tags, i), state
	end
	return

append_names_to_file: procedure expose (globals) states.
	parse arg filename, dir, tag, state
	n = value('states.'||state||'.'||tag||'.0')
	if n > 0 then do
		if stream(filename, 'c', 'open write') \= 'READY:' then
			call die 'Cannot open for append file '||filename||'.'
		call lineout filename, dir
		call lineout filename, tag
		do i = 1 to n
			call lineout filename,,
				value('states.'||state||'.'||tag||'.'||i)
		end
		call stream filename, 'c', 'close'
	end
	return

write_logfile: procedure expose (globals) text.
	parse arg filename
	call SysFileDelete translate(filename, '\', '/')
	if stream(filename, 'c', 'open write') \= 'READY:' then
		call die 'Cannot open for write log file '||filename||'.'
	do i = 1 to text.0
		call lineout filename, text.i
	end
	call stream filename, 'c', 'close'
	return

/*
** Write these one day.
*/
change_summary_removed: procedure expose (globals) states.
	parse arg filename, tag
	return

change_summary_added: procedure expose (globals) states.
	parse arg filename, tag
	return

/*
** Do an 'cvs -Qn status' on each file in the arguments,
** and extract info.
*/
change_summary_changed: procedure expose (globals) states.
	parse arg filename, tag
	queue = rxqueue('create')
	call rxqueue 'set', queue
	do i = 1 to value('states.STATE_CHANGED.'||tag||'.0')
		file = value('states.STATE_CHANGED.'||tag||'.'||i)
		if file = '' then iterate
		'cvs -Qn status '||file||' | rxqueue '||queue
		rev = ''
		delta = ''
		rcsfile = ''
		do while queued() > 0
			line = space(translate(linein('queue:'), ' ', TAB))
			if pos('Repository revision:', line) = 1 then
				parse var line . ': ' rev ' ',
					(CVSROOT) '/' rcsfile ',v'
		end
		if rev \= '' & rcsfile \= '' then do
			'cvs -Qn log -N -r'||rev||' '||file||' | rxqueue '||queue
			do while queued() > 0
				line = linein('queue:')
				if pos('date:', line) = 1 then
					parse var line . 'lines:' delta
			end
		end
		call append_line filename, left(rev, 9)||left(delta, 12)||rcsfile
	end
	call rxqueue 'delete', queue
	return

read_line: procedure expose (globals)
	parse arg filename
	if stream(filename, 'c', 'open read') \= 'READY:' then
		call die 'Cannot open for read file '||filename||'.'
	line = linein(filename)
	call stream filename, 'c', 'close'
	return line

push_lines: procedure expose text. lines.
	do i = 1 to lines.0
		call push lines.i
	end
	return

format_lists: procedure expose lines. text.
	parse arg header
	files. = ''; files.0 = 0
	lastdir = ''
	lastsep = ''
	do i = 1 to lines.0
		if right(lines.i, 1) = '/' then do
			if lastdir \= '' then
      			call format_names lastdir
			lastdir = lines.i
			tag = ''
			files. = ''; files.0 = 0
		end
		else if tag = '' then do
			tag = lines.i
			if header||tag = lastsep then iterate
			lastsep = header||tag
			if tag = 'HEAD' then
				call push '  '||header||' files:'
			else
				call push '  '||left(header||' files:', 22)||,
					' (Branch: '||tag||')'
		end
		else do
			n = files.0+1
			files.n = lines.i
			files.0 = n
		end
	end
	call format_names lastdir
	return

format_names: procedure expose files. text.
	parse arg dir
	indent = length(dir)
	if indent < 20 then
		indent = 20
	line = '    '||left(dir, indent)
	do i = 1 to files.0
		if length(line)+length(files.i) > 66 then do
			call push line
			line = '    '||left('', indent)
		end
		line = line||' '||files.i
	end
	call push line
	return

mail_notification: procedure expose (globals) text.
	parse arg login
	from = read_author(login)
	call read_logfile MAIL_FILE||'.'||id, ''
	to = ''
	unique. = FALSE
	do i = 1 to lines.0
		do j = 1 to words(lines.i)
			word = word(lines.i, j)
			if pos('@', word) = 0 then iterate
			if unique.word then iterate
			unique.word = TRUE
			to = concat(to, word, ' ')
		end
	end
	if to = '' then return
	say 'Mailing the commit message...'
	filename = translate(TEMP_DIR||'/cvs-mail.?????', '\', '/')
	filename = SysTempFileName(filename)
	call stream filename, 'c', 'open write'
	call lineout filename, 'From:' from
	call lineout filename, 'To:' word(to, 1)
	if words(to) > 1 then
		call lineout filename, 'Bcc:' space(subword(to, 2),, ',')
	subject = 'Subject: cvs commit:'
	call read_logfile SUBJ_FILE||'.'||id, ''
	subjlines = 0; subjwords = 0
	do i = 1 to lines.0
		line = lines.i
		do j = 1 to words(line)
			if subjwords > 2 &,
					length(subject||' '||word(line, j)) > 75 then do
				if subjlines > 2 then
					subject = subject||' ...'
				call lineout filename, subject
				if subjlines > 2 then do
					subject = ''
					leave i
				end
				subject = '        '
				subjwords = 0
				subjlines = subjlines+1
			end
			subject = subject||' '||word(line, j)
			subjwords = subjwords+1
		end
	end
	if subject \= '' then
		call lineout filename, subject
	call lineout filename, ''
	do i = 1 to text.0
		call lineout filename, text.i
	end
	call stream filename, 'c', 'close'
	'@sendmail -odb -oem -t -a' filename
	call SysFileDelete translate(filename, '\', '/')
	return

find_authors: procedure expose (globals)
	parse arg env
	dir = value(env,, 'OS2ENVIRONMENT')
	if dir \= '' then if exists(dir||'/.cvsauthors') then
		return dir||'/.cvsauthors'
	return ''

read_author: procedure expose (globals)
	parse arg login
	filename = cvsauthors
	if filename = '' then do
		filename = find_authors('HOME')
		if filename = '' then
			filename = find_authors('ETC')
	end
	mailaddr = ''
	if filename \= '' then do
		if stream(filename, 'c', 'open read') \= 'READY:' then
			call die 'Cannot open' filename 'for reading.'
		do while lines(filename) > 0
			line = linein(filename)
			parse var line (login) '|' fullname '|' mailaddr
			if mailaddr \= '' then leave
		end
		call stream filename, 'c', 'close'
	end
	if mailaddr \= '' then do
		if fullname = '' then
			from = mailaddr
		else
			from = '"'||fullname||'" <'||mailaddr||'>'
	end
	else
		from = login||'@'||get_hostname()
	return from

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
	say 'Usage: '||argv.0||' [-?dbS] [-i infolevel] [-a authors]',
		'repository files...'
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
	call cleanup_tmpfiles
	exit EXIT_SIGNAL

