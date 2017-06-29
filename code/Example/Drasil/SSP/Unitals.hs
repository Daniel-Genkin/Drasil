module Drasil.SSP.Unitals where

import Language.Drasil
import Data.Drasil.SI_Units
import Data.Drasil.Quantities.SolidMechanics as SM
import Data.Drasil.Concepts.Physics as CP
import Data.Drasil.Units.Physics

sspSymbols :: [CQSWrapper]
sspSymbols = (map cqs sspConstrained) ++ (map cqs sspUnits) ++ (map cqs sspUnitless) 

---------------------------
-- Imported UnitalChunks --
---------------------------
{-
SM.mobShear, SM.shearRes, SM.stffness
SM.poissnsR, SM.elastMod <- ConstrainedChunks
-}
normStress = SM.nrmStrss
genForce = uc CP.force cF newton 
{-must import from Concept.Physics since Quantities.Physics has Force as a vector-}

-------------
-- HELPERS --
-------------
fsi, fisi :: String
fsi   = "for slice index i"
fisi  = "for interslice index i"

--------------------------------
-- START OF CONSTRAINEDCHUNKS --
--------------------------------

sspConstrained, sspOutputs :: [ConstrConcept]
sspInputs :: [UncertQ]
sspConstrained = map cCnptfromUQ sspInputs ++ sspOutputs
sspInputs  = [elasticMod, cohesion, poissnsRatio, fricAngle, dryWeight,
              satWeight, waterWeight]
sspOutputs = [fs, dx_i, dy_i]

gtZeroConstr :: [Constraint] --FIXME: move this somewhere in Data?
gtZeroConstr = [physc $ (:<) (Int 0)]

defultUncrt :: Double
defultUncrt = 0.1

elasticMod, cohesion, poissnsRatio, fricAngle, dryWeight, satWeight,
  waterWeight :: UncertQ
  
fs, dx_i, dy_i :: ConstrConcept

{-Intput Variables-}
--FIXME: add (x,y) when we can index or make related unitals

elasticMod = uq (constrained' SM.elastMod gtZeroConstr) defultUncrt 15000

cohesion     = uqc "c'" (cn $ "effective cohesion")
  "internal pressure that sticks particles of soil together"
  (prime $ Atomic "c") pascal Real gtZeroConstr defultUncrt 10

poissnsRatio = uq (constrained' SM.poissnsR
  [physc $ \c -> (Int 0) :< c :< (Int 1)]) defultUncrt 0.4

fricAngle    = uqc "varphi'" (cn $ "effective angle of friction")
  ("The angle of inclination with respect to the horizontal axis of " ++
  "the Mohr-Coulomb shear resistance line") --http://www.geotechdata.info
  (prime $ Greek Phi_V) degree Real [physc $ \c -> (Int 0) :< c :< (Int 90)]
  defultUncrt 25

dryWeight   = uqc "gamma" (cn $ "dry unit weight")
  "The weight of a dry soil/ground layer divided by the volume of the layer."
  (Greek Gamma_L) specific_weight Real gtZeroConstr
  defultUncrt 20

satWeight   = uqc "gamma_sat" (cn $ "saturated unit weight")
  "The weight of saturated soil/ground layer divided by the volume of the layer."
  (sub (Greek Gamma_L) (Atomic "Sat")) specific_weight Real gtZeroConstr
  defultUncrt 20

waterWeight = uqc "gamma_w" (cn $ "unit weight of water")
  "The weight of one cubic meter of water."
  (sub (Greek Gamma_L) lW) specific_weight Real gtZeroConstr
  defultUncrt 9.8

{-Output Variables-}
fs          = constrained' (cvR (dcc "FS" (nounPhraseSP $ "global factor of safety")
  "the stability of a surface in a slope") (Atomic "FS")) gtZeroConstr

dx_i        = cuc' "dx_i" (cn $ "displacement") ("in the x-ordinate direction " ++ fsi)
  (sub (Concat [Greek Delta_L, Atomic "x"]) lI) metre Real []

dy_i        = cuc' "dy_i" (cn $ "displacement") ("in the y-ordinate direction " ++ fsi)
  (sub (Concat [Greek Delta_L, Atomic "y"]) lI) metre Real []

---------------------------
-- START OF UNITALCHUNKS --
---------------------------

sspUnits :: [UCWrapper]
sspUnits = map ucw [normStress,
  coords, waterHght, slopeHght, slipHght, xi, critCoords,
  mobShrI, shrResI, shearFNoIntsl, shearRNoIntsl, slcWght, watrForce,
  watrForceDif, intShrForce, baseHydroForce, surfHydroForce,
  totNrmForce, nrmFSubWat, nrmFNoIntsl, surfLoad, baseAngle, surfAngle,
  impLoadAngle, baseWthX, baseLngth, surfLngth, midpntHght, genForce,
  momntOfBdy, genDisplace, SM.stffness, shrStiffIntsl, shrStiffBase,
  nrmStiffIntsl, nrmStiffBase, shrStiffRes, nrmStiffRes, shrDispl,
  nrmDispl, porePressure, elmNrmDispl, elmPrllDispl, 
  mobShrC, shrResC, rotatedDispl, intNormForce, shrStress]

normStress,
  coords, waterHght, slopeHght, slipHght, xi, critCoords, mobShrI,
  shearFNoIntsl, shearRNoIntsl, slcWght, watrForce, watrForceDif, shrResI,
  intShrForce, baseHydroForce, surfHydroForce, totNrmForce, nrmFSubWat,
  nrmFNoIntsl, surfLoad, baseAngle, surfAngle, impLoadAngle, baseWthX,
  baseLngth, surfLngth, midpntHght, genForce, momntOfBdy, genDisplace,
  shrStiffIntsl, shrStiffBase, nrmStiffIntsl, nrmStiffBase, shrStiffRes,
  nrmStiffRes, shrDispl, nrmDispl, porePressure, elmNrmDispl,
  elmPrllDispl, mobShrC, shrResC, rotatedDispl, intNormForce, shrStress :: UnitalChunk
  
{-FIXME: Many of these need to be split into term, defn pairs as
         their defns are mixed into the terms.-}

intNormForce = uc' "E_i" (cn $ "interslice normal force")
  ("exerted between adjacent slices " ++ fisi)
  (sub cE lI) newton

coords      = uc' "(x,y)"
  (cn $ "cartesian position coordinates" )
  ("y is considered parallel to the direction of the force of " ++
  "gravity and x is considered perpendicular to y")
  (Atomic "(x,y)") metre

waterHght   = uc' "y_wt,i"
  (cn $ "the y ordinate, or height of the water table at i")
  "refers to either slice i midpoint, or slice interface i"
  (sub lY (Atomic "wt,i")) metre

slopeHght   = uc' "y_us,i" (cn $ "the y ordinate, or height of the " ++
  "top of the slope at i")
  "refers to either slice i midpoint, or slice interface i"
  (sub lY (Atomic "us,i")) metre

slipHght    = uc' "y_slip,i" (cn $ "the y ordinate, or height of " ++
  "the slip surface at i")
  "refers to either slice i midpoint, or slice interface i"
  (sub lY (Atomic "slip,i")) metre

xi          = uc' "x_i"
  (cn $ "x ordinate")
  "refers to either slice i midpoint, or slice interface i"
  (sub lX lI) metre

critCoords  = uc' "(xcs,ycs)" (cn $ "the set of x and y coordinates")
  "describe the vertices of the critical slip surface"
  (Concat [sub (Atomic "{x") (Atomic "cs"), sub (Atomic ",y") (Atomic "cs"),
  Atomic "}"]) metre

mobShrI     = uc' "S_i" (cn $ "mobilized shear force")
  fsi
  (sub cS lI) newton

shrResI     = uc' "P_i" (cn $ "shear resistance") ("Mohr Coulomb frictional " ++
  "force that describes the limit of mobilized shear force the slice i " ++
  "can withstand before failure")
  (sub cP lI) newton
  
mobShrC     = uc' "Psi" (cn $ "constant") ("converts mobile shear without " ++ 
  "the influence of interslice forces, to a calculation considering the interslice forces")
  (sub (Greek Psi) lC) newton

shrResC     = uc' "Phi" (cn $ "constant") ("converts resistive shear without " ++ 
  "the influence of interslice forces, to a calculation considering the interslice forces")
  (sub (Greek Phi) lC) newton

shearFNoIntsl = uc' "T_i"
  (cn $ "mobilized shear force") ("without the influence of interslice forces" ++ fsi)
  (sub cT lI) newton

shearRNoIntsl = uc' "R_i"
  (cn $ "shear resistance") ("without the influence of interslice forces" ++ fsi)
  (sub cR lI) newton

slcWght     = uc' "W_i" (cn $ "weight") ("downward force caused by gravity on slice i")
  (sub cW lI) newton

watrForce    = uc' "H_i" (cn $ "interslice water force") ("exerted in the " ++
  "x-ordinate direction between adjacent slices " ++ fisi)
  (sub cH lI) newton

watrForceDif = uc' "dH_i" (cn $ "difference between interslice forces acting " ++ 
  "in the x-ordinate direction of the slice on each side") fisi
  (sub (Concat [Greek Delta, cH]) lI) newton

intShrForce = uc' "X_i" (cn $ "interslice shear force") 
  ("exerted between adjacent slices " ++ fisi)
  (sub cX lI) newton

baseHydroForce = uc' "U_b,i" (cn $ "base hydrostatic force")
  ("from water pressure within the slice " ++ fsi)
  (sub cU (Atomic "b,i")) newton

surfHydroForce = uc' "U_t,i" (cn $ "surface hydrostatic force")
  ("from water pressure acting into the slice from standing water on the slope surface " ++ fsi)
  (sub cU (Atomic "t,i")) newton

totNrmForce = uc' "N_i" (cn $ "normal force") ("total reactive force " ++
  "for a soil surface subject to a body resting on it")
  (sub cN lI) newton

nrmFSubWat = uc' "N'_i" (cn $ "effective normal force") ("for a soil surface, " ++
  "subtracting pore water reactive force from total reactive force")
  (sub (prime $ Atomic "N") lI) newton

nrmFNoIntsl = uc' "N*_i" (cn $ "effective normal force") ("for a soil surface, " ++
  "neglecting the influence of interslice forces")
  (sub (Atomic "N*") lI) newton

surfLoad    = uc' "Q_i" (cn $ "imposed surface load") 
  "a downward force acting into the surface from midpoint of slice i"
  (sub cQ lI) newton

baseAngle   = uc' "alpha_i" (cn $ "angle") ("base of the mass relative to the horizontal " ++ fsi)
  (sub (Greek Alpha_L) lI) degree

surfAngle   = uc' "beta_i" (cn $ "angle") ("surface of the mass relative to the horizontal " ++ fsi)
  (sub (Greek Beta_L) lI) degree

impLoadAngle = uc' "omega_i" (cn $ "angle")
  ("of imposed surface load acting into the surface relative to the vertical " ++ fsi)
  (sub (Greek Omega_L) lI) degree

baseWthX    = uc' "b_i" (cn $ "base width of a slice")
  ("in the x-ordinate direction only " ++ fsi)
  (sub lB lI) metre

baseLngth   = uc' "l_b,i" (cn $ "total base length of a slice") fsi
  (sub (Greek Ell) (Atomic "b,i")) metre

surfLngth   = uc' "l_s,i" (cn $ "length of an interslice surface")
  ("from slip base to slope surface in a vertical line from an interslice vertex " ++ fisi)
  (sub (Greek Ell) (Atomic "s,i")) metre

midpntHght  = uc' "h_i" (cn $ "midpoint height")
  ("distance from the slip base to the slope surface in a vertical line from the midpoint of the slice " ++ fsi)
  (sub lH lI) metre

momntOfBdy  = uc' "M" (cn $ "moment of a body") ("assumed 2D allowing a scalar")
  cM momentOfForceU --FIXME: move in concepts.physics ?

genDisplace = uc' "genDisplace" (cn $ "displacement") "generic displacement of a body"
  (Greek Delta_L) metre

shrStiffIntsl = uc' "K_st,i" (cn $ "shear stiffness")
  ("for interslice surface, without length adjustment " ++ fisi)
  (sub cK (Atomic "st,i")) pascal

shrStiffBase  = uc' "K_bt,i" (cn $ "shear stiffness") 
  ("for a slice base surface, without length adjustment " ++ fsi)
  (sub cK (Atomic "bt,i")) pascal

nrmStiffIntsl = uc' "K_sn,i" (cn $ "normal stiffness")
  ("for an interslice surface, without length adjustment " ++ fisi)
  (sub cK (Atomic "sn,i")) pascal

nrmStiffBase = uc' "K_bn,i" (cn $ "normal stiffness") 
  ("for a slice base surface, without length adjustment " ++ fsi)
  (sub cK (Atomic "bn,i")) pascal

shrStiffRes  = uc' "K_tr" (cn $ "shear stiffness")
  "residual strength"
  (sub cK (Atomic "tr")) pascal

nrmStiffRes  = uc' "K_no" (cn $ "normal stiffness")
  "residual strength"
  (sub cK (Atomic "no")) pascal

shrDispl = uc' "du_i" (cn $ "displacement")
  ("shear displacement " ++ fsi)
  (sub (Concat [Greek Delta_L, Atomic "u"]) lI) metre

nrmDispl = uc' "dv_i" (cn $ "displacement")
  ("normal displacement " ++ fsi)
  (sub (Concat [Greek Delta_L, Atomic "v"]) lI) metre
  
elmNrmDispl  = uc' "dt_i" (cn $ "displacement")
  ("for the element normal to the surface " ++ fsi)
  (sub (Concat [Greek Delta_L, Atomic "t"]) lI) metre
  
elmPrllDispl = uc' "dn_i" (cn $ "displacement")
  ("for the element parallel to the surface " ++ fsi)
  (sub (Concat [Greek Delta_L, Atomic "n"]) lI) metre

porePressure = uc' "mu" (cn "pore pressure") ("from water within the soil")
  (Greek Mu_L) pascal

rotatedDispl = uc' "varepsilon_i" (cn "displacement") ("in rotated coordinate system")
  (sub (Greek Epsilon_V) lI) metre
  
shrStress    = uc' "tau_i" (cn "shear stress") ("acting on the base of a slice")
  (sub (Greek Tau_L) lI) newton

----------------------
-- Unitless Symbols --
----------------------

sspUnitless :: [ConVar]
sspUnitless = [earthqkLoadFctr, normToShear,scalFunc, numbSlices, minFunction, fsloc]

earthqkLoadFctr, normToShear, scalFunc, numbSlices, minFunction, fsloc :: ConVar

earthqkLoadFctr = cvR (dcc "K_c" (nounPhraseSP $ "earthquake load factor") ("proportionality " ++
  "factor of force that weight pushes outwards; caused by seismic earth movements")) (sub cK lC)

normToShear = cvR (dcc "lambda" (nounPhraseSP $ "ratio") ("between interslice normal and " ++
  "shear forces (applied to all interslices)")) (Greek Lambda_L)

scalFunc    = cvR (dcc "f_i" (nounPhraseSP $ "scaling function") ("magnitude of interslice " ++
  "forces as a function of the x coordinate" ++ fisi ++ "; can be constant or a half-sine"))
  (sub lF lI)

numbSlices  = cvRs (dcc "n" (nounPhraseSP "number of slices") "the slip mass has been divided into")
  lN Natural

minFunction = cvR (dcc "Upsilon" (nounPhraseSP "function") ("generic minimization function or algorithm"))
  (Greek Upsilon)

fsloc       = cvR (dcc "FS_loci" (nounPhraseSP "local factor of safety") fsi)
  (sub (Atomic "FS") (Atomic "Loc,i"))