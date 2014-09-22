
Build/maintenance instructions for CVS 1.12 as of $Date: 2006/07/19 17:44:58 $

0. Prerequisites:
        EMX 0.9d
	a C shell (bash203.zip or ksh527rt.zip)
	GNU make (gnumake.zip)
	GNU text utils (gnututil.zip)
	GNU shell utils (gnusutil.zip)
	GNU file utils (gnufutil.zip)
	GNU sed (gnused.zip)
	GNU grep (gnugrep.zip)
	GNU awk (gnuawk.zip)
	GNU patch (gnupatch.zip)
	GNU diff utils (gnudiff.zip)
	GNU find (gnufind.zip)
	GNU crypt library (gnuufc.zip)
        GNU tar (gtar258.zip)
        GNU zip (gz124_32.zip)
	Texinfo to INF converter 1.00 (txict100.zip)
        IPFC (Watcom C/C++, VisualAge C++, Warp 4 Toolkit, DDK)

   All of  the above,  except for  IPFC, are  available  at the usual  places
   (Hobbes, LEO).  IPFC may be obtained either  from  the Developer's Toolkit
   (part of standard distribution  in OS/2 v 4.51+)  or from IBM DDK (look in
   the TOOLS.ZIP package).


1. Build process.

 * Unpack the CVS 1.12.x distribution (from http://cvs.nongnu.org).

 * Run 'patch -p0 -i x:/cvs/emx-new/diffs' from the cvs-1.12.x directory.

 * Unpack the emx-new archive into the cvs-1.12.x directory.

 * Change  to  the    emx-new directory  and  run   'make'   and  then  'make
   install_dir=x:/cvs install'. Replace   x:/cvs with the directory you  want
   CVS installed.  This  will copy  all  required files  to the  installation
   directory. To create a folder with  the CVS documentation book objects, go
   to the emx-new/book directory and run 'make installwps'.


2. Sanity check procedure.

   To perform  the sanity checks, run 'make check' for local repositories and
   'make remotecheck' for  remote repositories.  You do  not actually have to
   have  an   existing repository   to  run the  sanity  checks.   No network
   connection is  required for  'make remotecheck' as   it uses the  loopback
   interface. You need to  have the rshd that  comes with this port installed
   and ready to accept connections from the local  host, though.  The process
   of  setting  up rshd is  described in  README. Due to  the  way the remote
   sanity check works,  you need  to tell rshd to use sh to run programs.  Do
   this by either setting EMXSHELL=sh in your CONFIG.SYS or by replacing the
   line "start /min inetd" by "start /min  cmd /c "(set EMXSHELL=sh & inetd)"
   in x:\tcpip\bin\tcpstart.cmd.

   A word of wisdom: if you use BASH version 2.0.264,  there is a chance that
   you got TEST.EXE from this distribution on your  path. It's recommended to
   replace it with its equivalent from GNU sh-utils/coreutils. Moreover, with
   this particular version  of  BASH, some tests (e.g.  rcslib-diffrgx-1) are
   not operable due to single quotes ('') being lost  when a string parameter
   is passed along. The solution is to escape  them, e.g. \'\', or simply use
   a later version of BASH, or maybe PDKSH.

   The sanity   check  script now requires   recent versions  of  certain GNU
   utilities (e.g.   a new 'touch' that is   capable of handling  the unified
   timestamp format,  and an updated 'expr'). Unless  newer versions of these
   utilities are ported to OS/2, please  use the precompiled executables from
   the "sanity"  subdirectory  under  EMX-NEW. These executables  have  to be
   present on your PATH -  they are  not picked  up automatically from  their
   project subdirectory.

   Please also make sure that  SORT.EXE and RM.EXE come from  the GNU set (do
   not confuse GNU sort with the default OS/2  SORT.EXE, and avoid  alternate
   RM.EXE utilities that could  be found  in build tools, Tivoli Endpoint for
   Aurora, etc.). Non-GNU tools *will* misfire at certain steps of the sanity
   check, resulting in errors  at later steps.  These are very hard  to trace
   back.

   The  script now  runs much slower  on OS/2 because  a two-second delay (to
   account for timestamp  granularity) is now  introduced after  EACH call to
   CVS. This actually saves the maintainer a lot of time that would otherwise
   be wasted on inserting those wait cycles manually.


3. Advanced topics.

 * To  rebuild  the  configure  script from  scratch, one  will  have to  use
   specific  versions   of  configuration tools. GNU   autoconf   v 2.59c and
   automake v 1.9.6  are confirmed  to be  adequate  -- just don't forget  to
   include the "m4" directory, e.g. (in bash):
	aclocal -I m4 && automake && autoconf -I m4 && ./configure

   (You may encounter  all sorts of  unusual  problems with GNU Autotools  on
   OS/2. Get psyched up for disentangling M4-generated code.)

 * For    performance reasons,  the  usage of    recent GCC  releases may  be
   considered.  In this case it is strictly  necessary to use  GCC v 3.2.1 or
   similar  stable releases, or fall back  to  EMX/GCC v 2.8.1 otherwise. All
   versions in between  (PGCC v 2.95.x, GCC v  3.0.x) exhibit bugs with "-O2"
   optimization; sometimes the bugs are of an intermittent nature and will be
   hard  to discover  early,  e.g. eventually  CVS  may crash with  a SIGSEGV
   during  a  large  check-in  -  situations  like  this cannot  be  reliably
   prevented with the sanity check procedure!

 * As of March 16th 2003, CVS may  still be compiled for  a client-only setup
   using  the original  upstream  code without  these  patches. Several minor
   amendments will be needed, though:
   - Update emx/filesubr.c with new interfaces
   - Allow the repository path specification to include drive names (root.c)

 * "make CONTROLLED=1" will  yield a special  version  with  custom  syslog()
   output.  To insert  your  own  syslog()  checkpoints,  use  the  following
   conditional block:

   #ifdef CONTROLLED
       syslog (LOG_DEBUG, "parameter=%d", parameter);
   #endif

   This  facilitates debugging  and ensures  that none of the extra output is
   present in the release build.

 * Updating  "sanity.sh"  after  a  merge  with  new  upstream  code  usually
   involves a few routine operations:

   0. Walk  through  all merge conflicts.  Never  ignore  any changes  in the
      upstream code. Give a priority to upstream code  when  you decide which
      fragment to preserve in the merged version.

   1. The script shall never  presume that "sh" is the default shell on OS/2.
      To that  end, all  references  to "sh" and "/bin/sh" beyond the initial
      setup  stage are to  be replaced  with $TESTSHELL, and  invocations  of
      shell  commands should be  made more  explicit, e.g. by  enclosing  the
      arguments  into "sh -c 'args'",  see  the "info" group  of tests for an
      example.
   2. Error output starts  with "cvs" on  UNIX, "cvs.exe" on OS/2. Whenever a
      "dotest_fail"  routine counts  on a "cvs" prefix, replace "cvs"  either
      with   ${CPROG}  (Client Program)  or,  for server-specific tests, with
      ${SPROG} (Server Program).
   3. Search for "197" to see  if more  date  tests have  been added. Replace
      all  dates  in  1970...1979  range  with   19${DECADE}0....19${DECADE}9
      (be sure not to clobber shell variables with similar names).
   4. Some UNIX-specific  tests  will  have to  be  bypassed, e.g.  when  you
      encounter  mismatching  drwxrwxrwx  output from  CVS, just  enclose the
      entire block into a test for ${WONT_PRESERVE_PERMISSIONS}.


4. Distribution packaging.

   The packaging job is carried out by "make dist". If you want to maintain a
   port on your own, be sure to execute the sanity  check at least locally so
   that the quality traditions of "emx-new" are preserved. 

   Presently, the  OS/2  port  of  CVS   is wrapped into  ARJ   archives  (an
   open-source  edition of  ARJ is available  at http://arj.sourceforge.net),
   but the makefile may be easily modified for any other packaging method. 
