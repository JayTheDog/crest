!================================================================================!
! This file is part of crest.
!
! Copyright (C) 2021 - 2023 Philipp Pracht
!
! crest is free software: you can redistribute it and/or modify it under
! the terms of the GNU Lesser General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! crest is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU Lesser General Public License for more details.
!
! You should have received a copy of the GNU Lesser General Public License
! along with crest.  If not, see <https://www.gnu.org/licenses/>.
!================================================================================!

module api_helpers
  use iso_fortran_env,only:wp => real64,stdout => output_unit
  use strucrd
  use calc_type
  use iomod,only:makedir,directory_exist,remove
  !> APIs
  use tblite_api
  use gfn0_api
  use gfnff_api
  implicit none
  public

!=========================================================================================!
!=========================================================================================!
contains    !> MODULE PROCEDURES START HERE
!=========================================================================================!
!=========================================================================================!

!>--- printout routines directed to printout channels
  subroutine api_print_input_structure(pr,iunit,mol)
    implicit none
    !> INPUT
    logical,intent(in) :: pr
    integer,intent(in) :: iunit
    type(coord),intent(in) :: mol
    !> LOCAL
    integer :: i

    !> if printing is turned off, return
    if (.not.pr) return

    !> else, write structure info to the output unit
    write (iunit,'(a)') '# Input structure (in Ångström)'
    call mol%append(iunit)

    if (allocated(mol%lat)) then
      write (iunit,'(a)') '# Lattice vectors (in Ångström)'
      do i = 1,3
        write (iunit,'(3F16.8)') mol%lat(1:3,i)
      end do
    end if

    if (mol%chrg .ne. 0) then
      write (iunit,'(a)') '# Molecular charge'
      write (iunit,*) mol%chrg
    end if
    write (iunit,*)
  end subroutine api_print_input_structure

  subroutine api_print_e_grd(pr,iunit,mol,energy,gradient)
    implicit none
    !> INPUT
    logical,intent(in) :: pr
    integer,intent(in) :: iunit
    type(coord),intent(in) :: mol
    real(wp),intent(in) :: energy
    real(wp),intent(in) :: gradient(3,mol%nat)
    !> LOCAL
    real(wp) :: gnorm
    integer :: i

    !> if printing is turned off, return
    if (.not.pr) return

    !> else, write e+grd info to the output unit
    gnorm = sqrt(sum(gradient**2))
    write (iunit,*)
    write (iunit,'(a)') '# Total energy and gradient norm'
    write (iunit,*) energy,gnorm
    write (iunit,'(a)') '# Gradient'
    do i = 1,mol%nat
      write (iunit,'(3F20.10)') gradient(1:3,i)
    end do
    write (iunit,*)
  end subroutine api_print_e_grd

!=========================================================================================!

  subroutine api_handle_output(calc,fname,mol,pr)
    implicit none
    type(calculation_settings),intent(inout) :: calc
    character(len=*),intent(in) :: fname
    type(coord),intent(inout) :: mol
    logical,intent(out) :: pr
    character(len=:),allocatable :: cpath
    logical :: ex,reopen,append
    integer :: io

    pr = calc%pr .or. calc%prstdout
    append = calc%prappend
    reopen = .false.
    if (pr .and. .not.calc%prstdout) then
      inquire (unit=calc%prch,opened=ex)
      if ((calc%prch .ne. stdout).and.ex.and..not.append) then
        close (calc%prch)
        reopen = .true.
      end if
      if (.not.ex.and.(calc%prch .ne. stdout)) reopen = .true. !> for the first time the file needs opening
      if (allocated(calc%calcspace)) then
        ex = directory_exist(calc%calcspace)
        if (.not.ex) then
          io = makedir(trim(calc%calcspace))
        end if
        cpath = calc%calcspace//sep//fname
      else
        cpath = fname
      end if
      if (reopen) then
        !> NOTE: this requires a predifined print channel!
        open (unit=calc%prch,file=cpath)

      else
        write (calc%prch,'(/,a)') repeat('%',50)
        write (calc%prch,'(a)') '> new calculation'
        write (calc%prch,'(a,/)') repeat('%',50)
      end if
      deallocate (cpath)

      call api_print_input_structure(pr,calc%prch,mol)

    else if(pr.and.calc%prstdout)then
      calc%prch=stdout
    end if

  end subroutine api_handle_output

!=========================================================================================!
!>--- tblite helper/setup routines
  subroutine tblite_init(calc,loadnew)
    implicit none
    type(calculation_settings),intent(inout) :: calc
    logical,intent(out) :: loadnew
    loadnew = .false.
    if (.not.allocated(calc%tblite)) then
      allocate (calc%tblite)
      if(allocated(calc%tbliteparam))then
        calc%tblite%paramfile = calc%tbliteparam
      endif
      loadnew = .true.
    end if
    if (calc%apiclean) loadnew = .true.
  end subroutine tblite_init
  subroutine tblite_properties(calc,mol,iostatus)
!********************************************************
!* Obtain tblite-calculated properties (where available)
!********************************************************
    implicit none
    type(calculation_settings),intent(inout) :: calc
    type(coord),intent(in) :: mol
    integer,intent(out) :: iostatus
    integer :: chrg,uhf
    iostatus = 0
!> WBOs
    if (calc%rdwbo) then
      if (.not.allocated(calc%wbo)) &
      & allocate (calc%wbo(mol%nat,mol%nat),source=0.0_wp)
      call tblite_getwbos(calc%tblite,mol%nat,calc%wbo)
    end if
!> Molecular dipole moment
    if (calc%rddip) then
      chrg = calc%chrg
      uhf = calc%uhf
      call tblite_getdipole(mol,chrg,uhf,calc%tblite,calc%dipole)
    end if
!> Atomic charges
    if (calc%rdqat) then
      if (.not.allocated(calc%qat)) &
      & allocate (calc%qat(mol%nat),source=0.0_wp)
      call tblite_getcharges(mol,calc%tblite,calc%qat)
    end if
  end subroutine tblite_properties

!========================================================================================!

!>--- GFN0-xTB helper/setup routines
  subroutine gfn0_init(calc,g0calc,loadnew)
    implicit none
    type(calculation_settings),intent(inout) :: calc
    type(gfn0_data),intent(inout),allocatable  :: g0calc
    logical,intent(out) :: loadnew
    loadnew = .false.
    if (.not.allocated(g0calc)) then
      allocate (g0calc)
      loadnew = .true.
    end if
    if (calc%apiclean) loadnew = .true.
  end subroutine gfn0_init
  subroutine gfn0_init2(mol,calc,g0calc)
    implicit none
    type(coord),intent(in) :: mol
    type(calculation_settings),intent(inout) :: calc
    type(gfn0_data),intent(inout)  :: g0calc
#ifdef WITH_GFN0
    if (allocated(calc%solvent).and.allocated(calc%solvmodel)) then
      call gfn0_addsettings(mol,g0calc,calc%solvent,calc%solvmodel)
    end if
    if(calc%getlmocent) calc%rdwbo=.true.
    call gfn0_addsettings(mol,g0calc,loadwbo=calc%rdwbo)
#endif
  end subroutine gfn0_init2
  subroutine gfn0_init3(mol,calc,g0calc)
    implicit none
    type(coord),intent(in) :: mol
    type(calculation_settings),intent(inout) :: calc
    type(gfn0_data),intent(inout),allocatable  :: g0calc
    integer :: nel,uhf
#ifdef WITH_GFN0
    nel = g0calc%wfn%nel
    uhf = calc%uhf
    call g0calc%wfn%refresh_occu(nel,uhf)
    call gfn0_addsettings(mol,g0calc,etemp=calc%etemp)
#endif
  end subroutine gfn0_init3
  subroutine gfn0_properties(calc,g0calc,mol,iostatus)
    implicit none
    type(calculation_settings),intent(inout) :: calc
    type(gfn0_data),intent(inout) :: g0calc
    type(coord),intent(in) :: mol
    integer,intent(out) :: iostatus
    iostatus = 0
#ifdef WITH_GFN0
!>--- Bond orders
    if (calc%rdwbo) then
      if (.not.allocated(calc%wbo)) &
      & allocate (calc%wbo(mol%nat,mol%nat),source=0.0_wp)
      call gfn0_getwbos(g0calc,mol%nat,calc%wbo)
    end if
!>--- dipole moments
    if (calc%rddip) then
      call gfn0_getdipole(g0calc,mol,calc%dipole)
    end if
    if (calc%rdqat)then
       if(.not.allocated(calc%qat)) &
       & allocate (calc%qat(mol%nat), source=0.0_wp)
       call gfn0_getqat(g0calc,mol,calc%qat) 
    endif
    if (calc%getlmocent)then
       call gfn0_getlmocent(g0calc,mol,calc%nprot,calc%protxyz)
    endif
#endif
  end subroutine gfn0_properties

!========================================================================================!

!>--- GFN0*-xTB setup/helper routines
  subroutine gfn0occ_init(calc,g0calc,loadnew)
    implicit none
    type(calculation_settings),intent(inout) :: calc
    logical,intent(out) :: loadnew
    type(gfn0_data),intent(inout),allocatable  :: g0calc
    integer :: nel,nao,nlev
    loadnew = .false.
#ifdef WITH_GFN0
    if (.not.allocated(g0calc)) then
      allocate (g0calc)
      loadnew = .true.
    end if
    if (calc%apiclean) loadnew = .true.
#endif
  end subroutine gfn0occ_init
  subroutine gfn0occ_init2(mol,calc,g0calc)
    implicit none
    type(coord),intent(in) :: mol
    type(calculation_settings),intent(inout) :: calc
    type(gfn0_data),intent(inout),allocatable  :: g0calc
    integer :: nel,nao,nlev
#ifdef WITH_GFN0
    if (allocated(calc%solvent).and.allocated(calc%solvmodel)) then
      call gfn0_addsettings(mol,g0calc,calc%solvent,calc%solvmodel)
    end if
    call gfn0_addsettings(mol,g0calc,etemp=calc%etemp,loadwbo=calc%rdwbo)
#endif
  end subroutine gfn0occ_init2
  subroutine gfn0occ_init3(mol,calc,g0calc)
    implicit none
    type(coord),intent(in) :: mol
    type(calculation_settings),intent(inout) :: calc
    type(gfn0_data),intent(inout),allocatable  :: g0calc
    integer :: nel,nao,nlev
#ifdef WITH_GFN0
    if (.not.allocated(calc%occ)) then
      nel = g0calc%wfn%nel
      nao = g0calc%basis%nao
      if (allocated(calc%occ)) deallocate (calc%occ)
      allocate (calc%occ(nao),source=0.0_wp)
      call gfn0_gen_occ(nel,nao,calc%config,calc%occ)
    end if
#endif
  end subroutine gfn0occ_init3

!========================================================================================!

!>--- GFN-FF setup/helper routines
  subroutine gfnff_init(calc,loadnew)
    implicit none
    type(calculation_settings),intent(inout) :: calc
    logical,intent(out) :: loadnew
    integer :: nel,nao,nlev
    loadnew = .false.
#ifdef WITH_GFNFF
    if (.not.allocated(calc%ff_dat)) then
      allocate (calc%ff_dat)
      loadnew = .true.

      !> some restart options
      calc%ff_dat%restart = calc%restart
      if (allocated(calc%restartfile)) then
        calc%ff_dat%restartfile = calc%restartfile
      end if
      if (allocated(calc%refgeo)) then
        calc%ff_dat%refgeo = calc%refgeo
      end if
      if (allocated(calc%parametrisation)) then
        calc%ff_dat%refgeo = calc%parametrisation
      end if
      if (allocated(calc%refcharges)) then
        calc%ff_dat%refcharges = calc%refcharges
      end if

    end if
    if (allocated(calc%solvent)) then
      if (.not.allocated(calc%ff_dat%solvent)) then
        allocate (calc%ff_dat%solvent,source=trim(calc%solvent))
        calc%ff_dat%solvent = calc%solvent
      end if
    end if
    if (calc%apiclean) loadnew = .true.
#endif
  end subroutine gfnff_init
  subroutine gfnff_properties(calc,mol,iostatus)
    implicit none
    type(calculation_settings),intent(inout) :: calc
    type(coord),intent(in) :: mol
    integer,intent(out) :: iostatus
    integer :: i,j
    iostatus = 0
#ifdef WITH_GFNFF
    if (calc%rdwbo) then
      if (allocated(calc%wbo)) deallocate (calc%wbo)
      allocate (calc%wbo(mol%nat,mol%nat),source=0.0_wp)
      call gfnff_getwbos(calc%ff_dat,mol%nat,calc%wbo)
    end if
    if (calc%rddip) then
      calc%dipole = matmul(calc%ff_dat%nlist%q,transpose(mol%xyz))
    end if
   if (calc%rdqat)then
       if(.not.allocated(calc%qat)) &
       & allocate (calc%qat(mol%nat), source=0.0_wp)
       calc%qat = calc%ff_dat%nlist%q
   endif
   if(allocated(calc%getsasa))then
     call gfnff_dump_sasa(calc%ff_dat,mol%nat,calc%getsasa)
   endif
#endif
  end subroutine gfnff_properties

!========================================================================================!

!>--- LIBPVOL setup/helper routines
  subroutine libpvol_initcheck(calc,loadnew)
    implicit none
    type(calculation_settings),intent(inout) :: calc
    logical,intent(out) :: loadnew
    loadnew = .false.
#ifdef WITH_LIBPVOL
    if (.not.allocated(calc%libpvol)) then
      allocate (calc%libpvol)
      loadnew = .true.
    end if
    if (calc%apiclean) loadnew = .true.
#endif
  end subroutine libpvol_initcheck

!========================================================================================!
!========================================================================================!
end module api_helpers
