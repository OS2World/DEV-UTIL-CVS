#
# $Id: fix-diff.awk,v 1.1.3.1 1999/06/17 15:20:45 root Exp $
#
# This awk script adds the directory prefix to the file names in
# "cvs diff -c" generated diffs so "patch -p0 -i diffs" will find
# the file to patch, even if it is not in the current directory.
# It also removes empty diffs.
#
# Usage:
#  cvs -Q diff -c | awk -f fix-diff.awk >diffs
#
# Copyright (C) 1998  Andreas Huber <ahuber@ping.at>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; see the file COPYING. If not, write to
# the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
# Boston, MA 02111-1307, USA.
#
/^Index: .*$/, /^\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*$/ {
	if ($0 ~ /^Index: .*$/) {
		file = $2
		nlines = 0
		delete linebuf
	}
	if ($0 ~ /^(\*\*\*|---)[ 	][^ 	]*[ 	][0-9]+\/[0-9]+\/[0-9]+[ 	][0-9]+:[0-9]+:[0-9]+([ 	][0-9.]*)?$/) {
		linebuf[nlines++] = gensub($2, file, 1)
		next
	}
	if ($0 ~ /^\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*$/) {
		for (i = 0; i < nlines; ++i) {
			print linebuf[i]
		}
		print $0
		next
	}
	linebuf[nlines++] = $0
	next
}
{
	if ($0 !~ /^\? /)
		print $0
}

