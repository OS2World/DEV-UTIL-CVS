/*
** $Id: verifymsg.cmd,v 1.1.3.1 1999/06/17 15:20:46 root Exp $
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
EXIT_SUCCESS		= 0
EXIT_FAILURE		= 1
EXIT_SIGNAL			= 3

FALSE				= 0
TRUE				= \FALSE

/*
** Global names known to all procedures.
*/
globals = 'EXIT_SUCCESS EXIT_FAILURE EXIT_SIGNAL',
	'FALSE TRUE argv.0'

/*
** Main body.
*/
main:
	argv.0 = 'verifymsg'
	signal on halt name signal_handler
	exit EXIT_FAILURE

signal_handler:
	call lineout 'stderr:', argv.0||': terminated by SIGINT.'
	exit EXIT_SIGNAL

