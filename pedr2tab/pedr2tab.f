c program pedr2tab.f for (small-endian) PC
c ----------------------------------------------------------------------
c output ASCII table of MOLA shot values from PEDR binary files
c The PDS label is checked for SFDU and software keyword.
c ----------------------------------------------------------------------
c input preferences from PEDR2TAB.PRM
c ----------------------------------------------------------------------
c Version 2.71828, applies parallax and crossover correction
c Refer to PEDR Software Interface Specification, Version 2.7,
c http://ltpwww.gsfc.nasa.gov/tharsis/pedrsis-2-7.html
c sets filetab to local directory, extends orbit number, aflag
c ----------------------------------------------------------------------
c written in Fortran-77 for IEEE-std, big-endian machines, with some
c language extensions and system functions that may cause errors:
c
c variable names may be longer than, but are unique to six letters
c
c The $ format descriptor extension is used to output to the
c format buffer without end-of-line terminators.
c
c The byte data type extension is used to decode signed 1 byte values,
c sometimes referred to as integer*1
c
c Direct access I/O is used to read binary unformatted data.
c For DEC compilers, redefine the "recl=776" keyword to "recl=194"
c
c ----------------------------------------------------------------------
	implicit real*8 (a-h,o-z)
	parameter (pi=3.141592653589793d0)
	parameter (d2r=pi/180.d0,r2d=180.d0/pi)
	parameter (irecl=776)!bytes for all but DEC compilers
c 	parameter (irecl=194)!words for DEC VAX,ALPHA
	integer*4 iswap4, a
	integer*2 iswap2, j
cMS	integer*2 iargloc
 	logical lhdr, lall,lgrd,lpr(0:7),obf,usgs, first,lxovr,list
	character*64 filelist, file2, filestring, filetab, filename
	character*16 ltmn,ltmx,lnmn,lnmx
	character*8 ccsd
	real*4 yth(4)
	integer bkgrd,mask
	integer*2 iwant,loctime,iphase,incidence,iemission,aflag
	integer*2 mgmver,mgm2
c The PEDR data frame:
	integer*4 pedr(194)
	integer*2 ipdr(388)
	byte      bpdr(776)
	equivalence (pedr,ipdr,bpdr)
c this equivalence for string search in header:
	character*776 cpdr
	equivalence (cpdr,bpdr)
c some values are accessed conveniently through equivalences:
	equivalence (loctime, ipdr(271))
	equivalence (iphase, ipdr(272))
	equivalence (incidence, ipdr(273))
	equivalence (iemission, ipdr(274))
	data filelist /'FILELIST'/
	data file2 /'MOLA.TAB'/
	data dlatdr /0./, dlondr/0./, xcorr /0./,dxcor/0./!versions <3
	data dltmn/-90.d0/,dltmx/90.d0/,dlnmn/-360.d0/,dlnmx/360.d0/
c
	data mask/Z'3FFF'/ !packet counter bits 13-0
	data yth /2.29,1.32,0.763,0.440/ !threshold voltage gain factors
	data lall /.FALSE./ ! all shot returns
	data lgrd /.TRUE./ !  ground returns
	data iwant /1/ ! shot_classification_flag =0 => clouds or noise,
c                                             =1 => ground return
	data lhdr /.TRUE./,obf /.FALSE./! two header lines, one big file
	data lpr /1*.TRUE.,7*.FALSE./, first /.TRUE./! selected values
	data usgs /.FALSE./ ! areographic coordinates?
	data lxovr /.TRUE./ ! crossover corrections if true 
	data list /.TRUE./ ! read from filelist 
	data mgm2 /2/	!first version with parallax
c PEDR 4-byte integer values:
c	1: frame mid-point whole seconds past J2000
c	2: frame mid-point fractional microseconds past J2000
c	3: rev number
c	4: sc areocentric lat deg*1000000
c	5: sc lon deg*1000000
c	6: mgs radial distance
c	7: mid-point range (cm)
c	8: bad shot bits (1=bad)
c	9-12 quality bit flags
c	13-32 shot planetary radii (cm)
c	33: midpoint planetary radius (cm)
c	34: right ascension
c	35: declination
c	36: twist
c	--> 37-46 rcv pulse energy 
c	--> 47-56 reflectivity-transmissivity product 
c	--> 57-61 channel number bytes
c	--> 62-71 pulsewidth at threshold crossing
c	--> 72-81 pulsewidth at threshold crossing
c	82-83: parallax dlat/dr and dlon/dr
c	84: drift function derived from crossovers
c	85: frame midlat deg*1000000
c	86: frame midlon deg*1000000
c	--> 87-96 laser transmit energy
c	--> 97-106 shot classification codes
c       --> 107-114 background noise counts
c       115 range window delay, cm
c       116 range window width, cm
c       --->117-134 other engineering data
c	--->135-137: flags and angles 
c	138: opacity
c       139-140: frame midpoint time, IEEE-double 
c       140-150: pulse width-area counts 
c	151: delta_sc_lat 
c	152: delta_sc_lon 
c	153: delta_sc_rad cm
c	154 areoid radius
c	155 off-nadir pointing angle, deg*1000000 
c	161 delta areoid
c	162 MOLA clock frequency
c	163-182 MOLA_range (cm)
c	193 delta-latitude 
c	194 delta-longitude

c ipdr 2-byte integer values:
c	246 frame index, 1-7
c	248 packet number, bits 13-0
c	254 fine time code
c	269 orbit code
c	270 attitude code
c	271 local time
c	272 solar phase
c	273 solar incidence
c	274 laser emission
c	365-384 range correction (cm)

c bpdr 1-byte values
c       225-244: trigger channel
c       561-580: received energy counts
c       581-600: pulse width counts
c ----------------------------------------------------------------------
      iswap2(j)=ior(ishft(iand(j,Z'FF'),8),iand(ishft(j,-8),Z'FF'))
c
      iswap4(a)=ior(ior( ior(ishft(a,24),iand(ishft(a,8),Z'00FF0000')),
     1                                   iand(ishft(a,-8),Z'0000FF00')),
     2                                   iand(ishft(a,-24),Z'000000FF'))
c ----------------------------------------------------------------------
c execution begins with flattening default value (Viking MDIMS):
	
	aob2 = (3393.4d0/3375.73d0)**2

c  input format preferences

	open(unit=1,file='PEDR2TAB.PRM',status='old',err=1)
	read(1,*,end=1,err=1) lhdr
	do i=0,7
	 read(1,*,end=1,err=1) lpr(i)
	enddo
	usgs = lpr(2) !Areographic needed
	read(1,*,end=1,err=1) lall
	read(1,*,end=1,err=1) lgrd
	read(1,*,end=1,err=1) lxovr
	read(1,*,end=1,err=1) obf , file2
c	write(*,*)'File2=', file2
	read(1,*,end=1,err=1) dlnmn
	read(1,*,end=1,err=1) dlnmx
	read(1,*,end=1,err=1) dltmn
	read(1,*,end=1,err=1) dltmx

	read(1,*,end=1,err=1) flatn
	aob2 = 1./(1. - 1./flatn)**2
c	read(1,*,end=1,err=1) usgs
	goto 2
 1	continue
	write(*,*)' PEDR2TAB.PRM not found or wrong format'
 2	continue
	close(1)
c ----------------------------------------------------------------------
	write(*,*) '   Output parameters (PEDR2TAB.PRM): '
	write(*,*) '   -------------------------------- '
	write(*,*) ' Header lines:                      ',lhdr
	write(*,*) ' shot location, topo, flags:        ',lpr(0)
	write(*,*) ' MGS location:                      ',lpr(1)
	write(*,*) ' angle, ET, areodetic_lat, areoid:  ',lpr(2)
	write(*,*) ' shot #, packet #, rev #, GMM #:    ',lpr(3)
	write(*,*) ' solar time, phase, incidence:      ',lpr(4)
	write(*,*) ' range walk & pulse statistics:     ',lpr(5)
	write(*,*) ' background, threshold, raw pulse:  ',lpr(6)
	write(*,*) ' range window, range delay:         ',lpr(7)
	write(*,*) ' selected (F) or all (T) shots:     ',lall
	write(*,*) ' noise/clouds (F), ground shots (T):',lgrd
	if(lgrd) then
	 iwant =1
	else
	 iwant =0
	endif
	write(*,*) ' apply crossover corrections:       ',lxovr
	write(*,*) ' template filetype or one big file :',obf
	id=index(file2,".")
	
 	write(*,10)' lon. (positive East):',dlnmn,' to',dlnmx
 	write(*,10)' lat. (areocentric):  ',dltmn,' to',dltmx
 10     format(2(a,f9.2))
	if (usgs) write(*,10) ' Flattening (areographic): ',flatn
c ----------------------------------------------------------------------
	if (iargc().gt.0) then
	iargloc=1
	 call getarg(iargloc,filelist)
	else
	 write(*,*)
	 write(*,*)' PEDR or List of Binary PEDR Files:'
	 read(*,'(a)',end=3) filelist
	endif
 3	open(unit=4,file=filelist,status='old',err=9999)
c	inquire(unit=4, name=filelist)
	if(index(filelist,".b").gt.0 .or.index(filelist,".B").gt.0)then
	  list = .false.!assume PEDR, check first 8 chars of SFDU
 	  read(4,'(a)',end=999) ccsd
	  if(ccsd.eq."CCSD3ZF0") then
	   filestring=filelist
	   close(4)
	  else
	   write(*,*)'Invalid PEDR header! ', ccsd
	   goto 9999
	  endif
	else    !leave 4 open for loop
	   write(*,*)'List of PEDR files'
	  list = .true.
	endif
c One Big File?
	if(obf) open(unit=2,file=file2,status='unknown',
     & iostat=iopen,err=9999)

	ict=0
c ----------------------------------------------------------------------
c Loop over input files
c ----------------------------------------------------------------------

 4	continue
	if (list) read(4,'(a)',end=99) filestring
 	idot=index(filestring,".b")
 	if (idot.eq.0) idot=index(filestring,".B")
c	write(*,*) idot, filestring(1:idot)
 	if (idot.eq.0) then
 	 write(*,*)'Filename must have valid extension'
 	 write(*,*)'skipping "',filestring,'"' 
 	 close (1)
 	 if (list) goto 4
 	endif
 	write(*,'(a,a)')' Opening:',filestring(1:idot+1)
	open(unit=1,file=filestring,status='old',iostat=iopen,
     &  access='direct',recl=irecl,err=99)

	inquire(unit=1, name=filename)
	idot=index(filename,".")
c test version
	read(1,rec=1,err=9) pedr !label
	isoft=index(cpdr,"SOFTWARE_NAME =")
	if (isoft.gt.0) then
	 read(unit=cpdr(isoft+25:isoft+28),fmt=*) version
	 write(*,'(a,f5.2)')' software is',version
	 if (version.lt. 7.125) then
	 write(*,*) cpdr(isoft:isoft+29),' lacks xovers'
	 lxovr = .false.
	 endif
	 if (version.le.7.0d0) mgm2 = 3
	else
c die?
	 write(*,*) 'SOFTWARE_NAME not found'
 	 if (list) goto 4
	endif

c ----------------------------------------------------------------------
	if(.not. obf) then
	 filetab = filename(idot-8:idot)//file2(id+1:id+3)
c	 filetab = filename(1:idot)//file2(id+1:id+3)
 	 open(unit=2,file=filetab,
     &   status='unknown',
     &   iostat=iopen,err=999)
	 write(*,*)'writing: ', filetab
	 first = .true.
	endif

	if (lhdr .and. first) then
c headings	
	  if(lpr(0)) write(2,8000)
	  if(lpr(1)) write(2,8001)
	  if(lpr(2)) write(2,8002)
	  if(lpr(3)) write(2,8003)
	  if(lpr(4)) write(2,8004)
	  if(lpr(5)) write(2,8005)
	  if(lpr(6)) write(2,8006)
	  if(lpr(7)) write(2,8007)
	  write(2,8008)
	  if(lpr(0)) write(2,8010)
	  if(lpr(1)) write(2,8011)
	  if(lpr(2)) write(2,8012)
	  if(lpr(3)) write(2,8013)
	  if(lpr(4)) write(2,8014)
	  if(lpr(5)) write(2,8015)
	  if(lpr(6)) write(2,8016)
	  if(lpr(7)) write(2,8017)
	  write(2,8008)
	  first = .false.
	endif
	read(1,rec=11,err=9) pedr !first frame
	dptime=iswap4(pedr(1)) + 1.d-06*iswap4(pedr(2))
	etime0=(dptime-1.) !time of first frame
c BAG to set slope of correction function at second frame
	icorr=iswap4(pedr(84))
	mgmver=iswap2(ipdr(269))
	if (mgmver.ge.mgm2) then
c crossover corrector, once per frame
	 lastxc = icorr
	 read(1,rec=12,err=9) pedr
	 icorr=iswap4(pedr(84))
	 lastxc = lastxc - (icorr-lastxc)
	endif
c
	ifound=0
	do i=1,99999
	 read(1,rec=i+10,err=9) pedr
	 dptime=iswap4(pedr(1)) + 1.d-06*iswap4(pedr(2))
	 irev = iswap4(pedr(3))
  	 iseq=iand(iswap2(ipdr(248)),mask)
	 dlat= 1.d-6*iswap4(pedr(85))
	 dlon= 1.d-6*iswap4(pedr(86))
c Check frame midpoint for bounds
	 if (dlat.ge.dltmn.and.dlat.le.dltmx
     &    .and.dlon.ge.dlnmn.and.dlon.le.dlnmx) then
	 ifound=ifound+1
	 mgmver=iswap2(ipdr(269))
c parallax and drift corrections
	 if (mgmver.ge.mgm2) then
	  dlatdr =1.d-9*iswap4(pedr(82))
	  dlondr =1.d-9*iswap4(pedr(83))
c crossover corrector, once per frame
	  if (lxovr) then
	   icorr=iswap4(pedr(84))
	   xcorr  = 1.d-2*icorr
	   dxcor  = 1.d-2*(icorr-lastxc)
	   lastxc = icorr
	  endif
	 endif
c mola clock frequency, scaled
	 f = 1.d-9*iswap4(pedr(162))
	 flat= 1.d-6*iswap4(pedr(4))
	 flon= 1.d-6*iswap4(pedr(5))
	 fscrad=1.d-2*iswap4(pedr(6))
	 dmidrange=1.d-2*iswap4(pedr(7))
	 fplrad=1.d-2*iswap4(pedr(33))
	 rdelay=1.d-2*iswap4(pedr(115))
	 rwnd=1.d-2*iswap4(pedr(116))
	 dslatdt=1.d-6*iswap4(pedr(151))
	 dslondt=1.d-6*iswap4(pedr(152))
	 draddt=1.d-2*iswap4(pedr(153))
	 fref  =1.d-2*iswap4(pedr(154))
	 drefdt=1.d-2*iswap4(pedr(161))
	 dlatdt=1.d-6*iswap4(pedr(193))
	 dlondt=1.d-6*iswap4(pedr(194))
	 aflag=iswap2(ipdr(270))
c scale angles	 
	 hourlocal = 12.d0 + iswap2(loctime)*0.0012d0/pi
 	 solarp  = iswap2(iphase)*0.0180d0/pi
 	 solari  = iswap2(incidence)*0.0180d0/pi
	 emission= iswap2(iemission)*0.0180d0/pi
	 offndr = 1.d-6*iswap4(pedr(155))
	 do k=1,20
	  molarg=iswap4(pedr(k+162))
	  if (molarg.gt.0 ! non-zero range returned
     &     .and. (lall .or.iswap2(ipdr(k+192)).eq. iwant)) then !output shot
	   ict=ict+1
c for each half-frame
	   i2 = (k-1)/10
	   ichan=bpdr(k+224)
c shot planetary radius (raw)
	   plrad = 0.01d0*iswap4(pedr(k+12))
	   x=(k-10.5d0)/20.d0
c MGS location
	   flatk = flat + x*dslatdt
	   flonk = flon + x*dslondt
	   if(flonk.lt.0.) flonk=flonk+360.d0
	   if(flonk.ge.360.d0) flonk=flonk-360.d0
c shot location corrected for parallax
	   dlatk = dlat + x*dlatdt+dlatdr*(plrad-fplrad)
	   dlonk = dlon + x*dlondt+dlondr*(plrad-fplrad)	   
	   if(dlonk.lt.0.) dlonk=dlonk+360.d0
	   if(dlonk.ge.360.d0) dlonk=dlonk-360.d0
c altimetry	   
	   plrad = plrad-xcorr-x*dxcor! after crossover corrections
	   range = 0.01d0*molarg
	   areoid = fref + x*drefdt
	   topo  = plrad - areoid
	   dmgsrad=fscrad+x*draddt
	   etime = dptime +(0.01d0/f)*(k-10.5d0)	   
	   if(usgs) phi= r2d*atan(aob2*tan(d2r*dlatk))
	   Rc = 0.01d0*iswap2(ipdr(k+364))
	   iframe = iswap2(ipdr(246))
           ishot=k+20*(iframe-1) ! 1-140 shot count	 
c "corrected, scaled received_pulse_energy"
 	   ErfJoule=iswap2(ipdr(k+72))
	   ireft = iswap2(ipdr(k+92))
	   if(ireft.lt.0) ireft=ireft+65536
 	   Reft=0.001*ireft ! Percent Reflectivity*Transmissivity
c raw counts stored as byte values
	   ipact=bpdr(k+560)
	   if(ipact.lt.0) ipact=ipact+256
	   ipwct=bpdr(k+580)
	   Pwt=0.1*iswap2(ipdr(k+122))
	   Sigopt=0.1*iswap2(ipdr(k+142))
	   Elaser=0.01*iswap2(ipdr(k+172))
 	   thrsh=iswap2(ipdr(232+4*i2+ichan))*yth(ichan)
c plog2 values are converted already in pproc 	      
 	   bkgrd=iswap4(pedr(106+4*i2+ichan))	      
c long lat topo range plan.radius chan att_flag
	   itmp = aflag
	   if(ipdr(k+192).eq.0) itmp=itmp+4
	   if(lpr(0))
     &      write(2,9000)dlonk,dlatk,topo,range,plrad,ichan,itmp
           if(lpr(1))write(2,9001) flonk, flatk, dmgsrad
           if(lpr(2))write(2,9002) offndr,etime,phi,areoid
           if(lpr(3))write(2,9003) ishot,iseq,irev,mgmver
           if(lpr(4))write(2,9004) hourlocal,solarp,solari
       	   if(lpr(5))write(2,9005)
     &        emission,Rc,Pwt,Sigopt,Elaser,ErfJoule,Reft
           if(lpr(6))write(2,9006) bkgrd,thrsh,ipwct,ipact
           if(lpr(7))write(2,9007) rwnd,rdelay
	   write(2,8008)
	  endif
	 enddo !end of shot loop
	 endif !end of bounds check
c
	enddo  !end of i/o loop
 9	continue
	close(unit=1)
	if (.not.obf) write(*,'(a,a)')' Closing: ', filetab
	if(.not.obf) close(unit=2)
	write(*,*)' Frames read: ', ifound
	write(*,*)' Total shots output: ', ict
	if (list) goto 4
99	continue
	close(unit=2)
999	write(*,*) ' Done!'
	close(4)
c ----------------------------------------------------------------------
c format statements
c ----------------------------------------------------------------------
9000     format(f9.5,f10.5,f11.2,f10.2,f12.2,2i2,$)
9001     format(2f10.5, f12.2,$)
9002     format(f8.3,f16.5,f10.5,f11.2,$)
9003     format(i4,i7,i8,i3,$)
9004     format(f7.3,2f7.2,$)
9005     format(f7.2,f7.2,2f8.1,f8.2,f7.0,f7.3,$)
9006     format(i7, f7.1,i3,i4,$)
9007     format(f7.0,f8.0,$)

8000	format(
     &  'long_East lat_North topography MOLArange  planet_rad c A',$)
8010	format(
     &  '---.-----  --.-----  ------.-- ------.-- --------.-- - -',$)
8001	format(
     &  '  SC_long   SC_lat     SC_radius',$)
8011	format(
     &  ' ---.----- ---.----- --------.--',$)
8002	format(
     &  '  offndr  EphemerisTime  areod_lat areoid_rad',$)
c8002	format(
c     &  ' offndr  EphemerisTime  areoid_rad',$)
8012	format(
     &  ' ---.--- ---------------  --.-----  ------.--',$)
c8012	format(
c     &  ' --.--- ---------------  ------.--',$)
8003	format(
     &  ' shot  pkt   orbit gm',$)
8013	format(
     &  ' ---  ----- ------ --',$)
8004	format(
     &  ' hrlcl  s_phas s_inc ',$)
8014	format(
     &  ' --.--- ---.-- ---.--',$)
8005	format(
     &  ' emissn  Rcorr     PWT  Sigopt  Elaser PulseE Ref*T%',$)
8015	format(
     &  ' ---.--  -----   ---.-  ------   ----- ------ --.---',$)
8006	format(
     &  '  bkgrd th_mV Wct Ect',$)
8016	format(
     &  '  ----- ------ -- ---',$)
8007	format(
     &  ' R_wnd   R_dly ',$)
8017	format(
     &  ' ------ -------',$)

8008    format(a)
c ----------------------------------------------------------------------
c normal return or error handling
c ----------------------------------------------------------------------
	goto 99999
9999	continue
	write(*,*)'Error ',iopen,' opening files'
99999	end

