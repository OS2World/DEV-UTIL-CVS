/*
** $Id: tokenize.cmd,v 1.1.3.1 1999/06/17 15:20:46 root Exp $
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

CVSROOT			= get_repository()

/*
** Global names known to all procedures.
*/
globals = 'EXIT_SUCCESS EXIT_FAILURE EXIT_SIGNAL',
	'FALSE TRUE argc argv. CVSROOT'

/*
** Main body.
*/
main:
/*
** Initialize basic variables.
*/
	argc = 1; argv. = ''; argv.0 = 'tokenize'
	signal on halt name signal_handler
	if CVSROOT = '' then
		call die 'Cannot tokenize in non-local repository (see CVSROOT).'
	filemask = CVSROOT||'/CVSROOT/*.cmd'
	call SysFileTree translate(filemask, '\', '/'),,
		'files.', 'fo', '*--+-'
	do i = 1 to files.0
		if left(filespec('n', files.i), 2) \= '.#' then do
			say 'Tokenizing' files.i
			'@attrib -r' files.i '>nul 2>&1'
			'@'||files.i '//t'
			'@attrib +r' files.i '>nul 2>&1'
		end
	end
	exit EXIT_SUCCESS

/*
** Subroutines.
*/
die: procedure expose (globals)
	parse arg text
	call lineout 'stderr:', argv.0||': '||text
	exit EXIT_FAILURE

get_repository: procedure
	cvsroot = value('CVSROOT',, 'OS2ENVIRONMENT')
	method = 'local'
	if left(cvsroot, 1) = ':' then
		parse var cvsroot ':' method ':' cvsroot
	if method \= 'local' then
		return ''
	return cvsroot

signal_handler:
	call lineout 'stderr:', argv.0||': terminated by SIGINT.'
	exit EXIT_SIGNAL

