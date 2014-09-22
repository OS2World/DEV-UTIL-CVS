/*
** $Id: install.cmd,v 1.1.3.1.4.1 2003/02/21 15:41:08 root Exp $
**
** Create a CVS folder and install the reference books.
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

EXIT_SUCCESS = 0
EXIT_FAILURE = 1

LOCATION = '<CVS_FOLDER>'

globals = 'EXIT_SUCCESS EXIT_FAILURE LOCATION'

main:
	if arg(1) \= '' then
		install_dir = arg(1)
	else
		install_dir = directory()
	call make_folder 'CVS'
	call make_book install_dir||'\intro.inf',,
		'CVS Introduction'
	call make_book install_dir||'\ossdev.inf',,
		'Open-Source Development with CVS'
	call make_book install_dir||'\cvs.inf',,
		'CVS Reference'
	call make_book install_dir||'\cvs-client.inf',,
		'CVS Client/Server Protocol Reference'
	exit EXIT_SUCCESS

make_folder: procedure expose (globals) LOCATION
	parse arg title
	if \SysCreateObject('WPFolder', title, '<WP_DESKTOP>',,
			'OBJECTID='||LOCATION, 'update') then
		call die 'Cannot create folder.'
	return

make_book: procedure expose (globals) LOCATION
	parse arg name, title
	name = translate(name, '\', '/')
	if \SysCreateObject('WPProgram', title, LOCATION,,
			'PROGTYPE=PM;EXENAME=VIEW.EXE;PARAMETERS='||name,,
	 		'update') then
		call die 'Cannot create books.'
	return

die: procedure expose (globals)
	parse arg text
	call lineout 'stderr:', text
	exit EXIT_FAILURE

