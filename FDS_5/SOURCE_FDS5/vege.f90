MODULE VEGE
 
USE PRECISION_PARAMETERS
USE GLOBAL_CONSTANTS
USE MESH_POINTERS
USE TRAN
USE PART
USE MEMORY_FUNCTIONS, ONLY:CHKMEMERR
USE TYPES, ONLY: DROPLET_TYPE, PARTICLE_CLASS_TYPE, PARTICLE_CLASS, WALL_TYPE
IMPLICIT NONE
PRIVATE
PUBLIC INITIALIZE_RAISED_VEG, RAISED_VEG_MASS_ENERGY_TRANSFER
TYPE (DROPLET_TYPE), POINTER :: DR
TYPE (PARTICLE_CLASS_TYPE), POINTER :: PC
CHARACTER(255), PARAMETER :: partid='$Id: part.f90 1290 2008-02-08 15:36:39Z ruddy@nist.gov $'
CHARACTER(255), PARAMETER :: partrev='$Revision$'
CHARACTER(255), PARAMETER :: partdate='$Date: 2008-02-08 10:36:39 -0500 (Fri, 08 Feb 2008) $'
LOGICAL, ALLOCATABLE, DIMENSION(:,:,:) :: VEG_PRESENT_FLAG,CELL_TAKEN_FLAG
INTEGER :: IZERO,NLP_VEG_FUEL,NCONE_TREE,NXB,NYB
REAL(EB) :: RCELL,R_TREE,XCELL,XI,YJ,YCELL,ZK
 
CONTAINS
 

SUBROUTINE INITIALIZE_RAISED_VEG(NM)

USE MEMORY_FUNCTIONS, ONLY: RE_ALLOCATE_DROPLETS
REAL(EB) DELTAZ_BIN,CANOPY_LENGTH,CANOPY_VOLUME,COSINE,TANGENT, &
         CANOPY_WIDTH
INTEGER NCT,NLP_TREE,NXB,NYB,NZB,NZBINS,IPC
INTEGER I
INTEGER, INTENT(IN) :: NM

IF (.NOT. TREE) RETURN !Exit if there are no trees anywhere
IF (.NOT. TREE_MESH(NM)) RETURN !Exit if raised veg is not present in mesh
IF (EVACUATION_ONLY(NM)) RETURN  ! Don't waste time if an evac mesh
CALL POINT_TO_MESH(NM)

ALLOCATE(VEG_PRESENT_FLAG(0:IBP1,0:JBP1,0:KBP1))
CALL ChkMemErr('VEGE','VEG_PRESENT_FLAG',IZERO)
ALLOCATE(CELL_TAKEN_FLAG(0:IBP1,0:JBP1,0:KBP1))
CALL ChkMemErr('VEGE','CELL_TAKEN_FLAG',IZERO)

TREE_LOOP: DO NCT=1,N_TREES

!  IF (TREE_MESH(NCT)/=NM) CYCLE TREE_LOOP
   VEG_PRESENT_FLAG = .FALSE. ; CELL_TAKEN_FLAG = .FALSE.
   IPC = TREE_PARTICLE_CLASS(NCT)
   PC=>PARTICLE_CLASS(IPC)
 
   ! Build a conical tree
   ! Put one fuel particle/element in each grid cell withing the conical volume 
   CANOPY_WIDTH  = CANOPY_W(NCT)
   CANOPY_LENGTH = TREE_H(NCT) - CANOPY_B_H(NCT)
   TANGENT = 0.5_EB*CANOPY_W(NCT)/CANOPY_LENGTH
   COSINE = CANOPY_LENGTH/SQRT(CANOPY_LENGTH**2 + (0.5_EB*CANOPY_WIDTH)**2)
   NZBINS = 1._EB/(1._EB-COSINE)
   DELTAZ_BIN = CANOPY_LENGTH/REAL(NZBINS,EB)
   CANOPY_VOLUME = PI*CANOPY_WIDTH**2*CANOPY_LENGTH/12.
 
   NLP_TREE = 0

   DO NZB=1,KBAR
     IF (Z(NZB).GE.Z_TREE(NCT)+CANOPY_B_H(NCT) .AND. Z(NZB).LE.Z_TREE(NCT)+TREE_H(NCT)) THEN
      PARTICLE_TAG = PARTICLE_TAG + NMESHES
!      R_TREE = TANGENT*(TREE_H(NCT)+Z_TREE(NCT)-Z(NZB)+0.5_EB*DZ(NZB))
      R_TREE = TANGENT*(TREE_H(NCT)+Z_TREE(NCT)-Z(NZB))
      DO NXB = 1,IBAR
       DO NYB = 1,JBAR
        RCELL = SQRT((X(NXB)-X_TREE(NCT))**2 + (Y(NYB)-Y_TREE(NCT))**2)
        IF (RCELL .LE. R_TREE) THEN
         NLP  = NLP + 1
         NLP_TREE = NLP_TREE + 1
         IF (NLP.GT.NLPDIM) THEN
          CALL RE_ALLOCATE_DROPLETS(1,NM,0,1000)
          DROPLET=>MESHES(NM)%DROPLET
         ENDIF
         DR=>DROPLET(NLP)
         DR%TAG = PARTICLE_TAG
         DR%X = REAL(NXB,EB)
         DR%Y = REAL(NYB,EB)
         DR%Z = REAL(NZB,EB)
         VEG_PRESENT_FLAG(NXB,NYB,NZB) = .TRUE.
         DR%SHOW = .TRUE.
         DR%CLASS = IPC
         DR%VEG_REP = 1
         DR%U = 0.
         DR%V = 0.
         DR%W = 0.
         DR%TMP = PC%VEG_INITIAL_TEMPERATURE + TMPM
         DR%T   = 0.
         DR%IOR = 0
         DR%VEG_FUEL_MASS = PC%VEG_BULK_DENSITY
         DR%VEG_MOIST_MASS = PC%VEG_MOISTURE*DR%VEG_FUEL_MASS
         DR%R =  2./PC%VEG_SV !cylinder, Porterie
         DR%VEG_PACKING_RATIO = PC%VEG_BULK_DENSITY/PC%VEG_DENSITY 
         DR%VEG_KAPPA = 0.25*PC%VEG_SV*PC%VEG_BULK_DENSITY/PC%VEG_DENSITY
         DR%VEG_EMISS = 4.*SIGMA*DR%VEG_KAPPA*DR%TMP**4
         TREE_MESH(NM) = .TRUE.
        ENDIF
       ENDDO   
      ENDDO 
     ENDIF
   ENDDO
   NLP_VEG_FUEL = NLP_TREE

! For the current vegetation type (particle classe) assign one fuel 
! element (droplet) to each grid cell and initialize droplet properties
! (this is precautionary needs more tested to determine its necessity)
   REP_VEG_ELEMS: DO I=NLP-NLP_VEG_FUEL+1,NLP
    DR=>DROPLET(I)
    DO NZB=1,KBAR
     DO NXB=1,IBAR
      GRID_LOOP: DO NYB=1,JBAR
       IF (.NOT. VEG_PRESENT_FLAG(NXB,NYB,NZB)) CYCLE GRID_LOOP
       IF (REAL(NXB,EB).EQ.DR%X .AND. REAL(NYB,EB).EQ.DR%Y .AND. REAL(NZB,EB).EQ.DR%Z) THEN 
        IF(CELL_TAKEN_FLAG(NXB,NYB,NZB)) THEN
         DR%R = 0._EB
         CYCLE REP_VEG_ELEMS
        ENDIF
        CELL_TAKEN_FLAG(NXB,NYB,NZB) = .TRUE.
        DR%X = X(NXB) - 0.5_EB*DX(NXB)
        DR%Y = Y(NYB) - 0.5_EB*DX(NYB)
        DR%Z = Z(NZB) - 0.5_EB*DZ(NZB)
        CYCLE REP_VEG_ELEMS
       ENDIF
      ENDDO GRID_LOOP
     ENDDO
    ENDDO
   ENDDO REP_VEG_ELEMS

ENDDO TREE_LOOP

CALL REMOVE_DROPLETS(0._EB,NM)

DEALLOCATE(VEG_PRESENT_FLAG)
DEALLOCATE(CELL_TAKEN_FLAG)

END SUBROUTINE INITIALIZE_RAISED_VEG




SUBROUTINE RAISED_VEG_MASS_ENERGY_TRANSFER(T,NM)
    
! Mass and energy transfer between gas and raised vegetation fuel elements 

USE PHYSICAL_FUNCTIONS, ONLY : GET_MASS_FRACTION2
USE MATH_FUNCTIONS, ONLY : AFILL2

!arrays for debugging
REAL(EB), POINTER, DIMENSION(:,:,:) :: HOLD1,HOLD2,HOLD3,HOLD4

REAL(EB) :: RE_D
REAL(EB) :: RDT,RVC,T
REAL(EB) :: K_AIR,MU_AIR,RHO_GAS,TMP_GAS,UBAR,VBAR,WBAR,UREL,VREL,WREL
REAL(EB) :: SV_VEG,TMP_VEG
REAL(EB) :: QCONV,QNET,QREL,TMP_GMV
REAL(EB) :: XI,YJ,ZK
INTEGER :: I,II,JJ,KK,IIX,JJY,KKZ,IPC
INTEGER, INTENT(IN) :: NM

!temporary
REAL(EB) :: RCP_TEMPORARY

IF (.NOT. TREE) RETURN !Exit if no raised veg anywhere
IF (.NOT. TREE_MESH(NM)) RETURN !Exit if raised veg is not present in mesh

! Initializations

RDT    = 1._EB/DT
RCP_TEMPORARY = 1._EB/CP_GAMMA

! Empirical coefficients

!D_AIR                  = 2.6E-5_EB  ! Water Vapor - Air binary diffusion (m2/s at 25 C, Incropera & DeWitt, Table A.8) 
!SC_AIR                 = 0.6_EB     ! NU_AIR/D_AIR (Incropera & DeWitt, Chap 7, External Flow)
!PR_AIR                 = 0.7_EB     

! Working arrays
D_VAP  = 0._EB

!Debugging arrays
HOLD1 => WORK4 ; WORK4 = 0._EB
HOLD2 => WORK5 ; WORK5 = 0._EB
HOLD3 => WORK6 ; WORK6 = 0._EB
HOLD4 => WORK7 ; WORK7 = 0._EB


DROPLET_LOOP: DO I=1,NLP

 DR => DROPLET(I)
 IPC = DR%CLASS
 PC=>PARTICLE_CLASS(IPC)
 IF (.NOT. PC%TREE) CYCLE DROPLET_LOOP
 IF (DR%R<=0._EB)   CYCLE DROPLET_LOOP

! Vegetation variables
 TMP_VEG = DR%TMP
 SV_VEG  = PC%VEG_SV

! Determine the current grid cell coordinates of the vegetation fuel element
 XI = CELLSI(FLOOR((DR%X-XS)*RDXINT))
 YJ = CELLSJ(FLOOR((DR%Y-YS)*RDYINT))
 ZK = CELLSK(FLOOR((DR%Z-ZS)*RDZINT))
 II  = FLOOR(XI+1._EB)
 JJ  = FLOOR(YJ+1._EB)
 KK  = FLOOR(ZK+1._EB)
 IIX = FLOOR(XI+0.5_EB)
 JJY = FLOOR(YJ+0.5_EB)
 KKZ = FLOOR(ZK+0.5_EB)
 UBAR = AFILL2(U,II-1,JJY,KKZ,XI-II+1,YJ-JJY+.5_EB,ZK-KKZ+.5_EB)
 VBAR = AFILL2(V,IIX,JJ-1,KKZ,XI-IIX+.5_EB,YJ-JJ+1,ZK-KKZ+.5_EB)
 WBAR = AFILL2(W,IIX,JJY,KK-1,XI-IIX+.5_EB,YJ-JJY+.5_EB,ZK-KK+1)
 UREL = DR%U - UBAR
 VREL = DR%V - VBAR
 WREL = DR%W - WBAR
 RVC = RDX(II)*RDY(JJ)*RDZ(KK)

! Gas variables in cell
 TMP_GAS  = TMP(II,JJ,KK)
 RHO_GAS  = RHO(II,JJ,KK)
 MU_AIR = SPECIES(0)%MU(MIN(500,NINT(0.1_EB*TMP_GAS)))
 K_AIR  = CPOPR*MU_AIR !W/m.K

! Variables for determining mass/heat transfer
 QCONV = 0._EB
 QNET  = 0._EB
 UREL  = DR%U
 QREL  = MAX(1.E-6_EB,SQRT(UREL*UREL + VREL*VREL + WREL*WREL))
 TMP_GMV = TMP_GAS - TMP_VEG


! Convective heat flux
 RE_D = RHO_GAS*QREL*2./(SV_VEG*MU_AIR)
 QCONV =SV_VEG*(0.5*K_AIR*0.683*RE_D**0.466)*0.5*TMP_GMV !W/m^2
 QCONV = SV_VEG*DR%VEG_PACKING_RATIO*QCONV


! Add mass and heat transfer contribution to divergence
 D_VAP(II,JJ,KK) = D_VAP(II,JJ,KK) - QCONV*RCP_TEMPORARY/(RHO_GAS*TMP_GAS)

ENDDO DROPLET_LOOP

! Remove vegetation that has completely burned 
 
CALL REMOVE_DROPLETS(T,NM)
 
END SUBROUTINE RAISED_VEG_MASS_ENERGY_TRANSFER

END MODULE VEGE
