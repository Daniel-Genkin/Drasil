## \file Calculations.py
# \author Nikitha Krithnan and W. Spencer Smith
# \brief Provides functions for calculating the outputs
import math

import Interpolation

## \brief Calculates stress distribution factor (Function) based on Pbtol
# \param inParams structure holding the input values
# \return stress distribution factor (Function) based on Pbtol
def func_J_tol(inParams):
    outfile = open("log.txt", "a")
    print("function func_J_tol called with inputs: {", file=outfile)
    print("  inParams = ", end='', file=outfile)
    print("Instance of InputParameters object", file=outfile)
    print("  }", file=outfile)
    outfile.close()
    
    return math.log(math.log(1 / (1 - inParams.P_btol)) * ((inParams.a * inParams.b) ** (7.0 - 1) / (2.86e-53 * (7.17e10 * inParams.h ** 2) ** 7.0 * inParams.LDF)))

## \brief Calculates applied load (demand): 3 second duration equivalent pressure (Pa)
# \param inParams structure holding the input values
# \return applied load (demand): 3 second duration equivalent pressure (Pa)
def func_q(inParams):
    outfile = open("log.txt", "a")
    print("function func_q called with inputs: {", file=outfile)
    print("  inParams = ", end='', file=outfile)
    print("Instance of InputParameters object", file=outfile)
    print("  }", file=outfile)
    outfile.close()
    
    return Interpolation.func_interpY("TSD.txt", inParams.SD, inParams.w_TNT)

## \brief Calculates dimensionless load
# \param inParams structure holding the input values
# \param q applied load (demand): 3 second duration equivalent pressure (Pa)
# \return dimensionless load
def func_q_hat(inParams, q):
    outfile = open("log.txt", "a")
    print("function func_q_hat called with inputs: {", file=outfile)
    print("  inParams = ", end='', file=outfile)
    print("Instance of InputParameters object", end='', file=outfile)
    print(", ", file=outfile)
    print("  q = ", end='', file=outfile)
    print(q, file=outfile)
    print("  }", file=outfile)
    outfile.close()
    
    return q * (inParams.a * inParams.b) ** 2 / (7.17e10 * inParams.h ** 4 * inParams.GTF)

## \brief Calculates tolerable load
# \param inParams structure holding the input values
# \param J_tol stress distribution factor (Function) based on Pbtol
# \return tolerable load
def func_q_hat_tol(inParams, J_tol):
    outfile = open("log.txt", "a")
    print("function func_q_hat_tol called with inputs: {", file=outfile)
    print("  inParams = ", end='', file=outfile)
    print("Instance of InputParameters object", end='', file=outfile)
    print(", ", file=outfile)
    print("  J_tol = ", end='', file=outfile)
    print(J_tol, file=outfile)
    print("  }", file=outfile)
    outfile.close()
    
    return Interpolation.func_interpY("SDF.txt", inParams.AR, J_tol)

## \brief Calculates stress distribution factor (Function)
# \param inParams structure holding the input values
# \param q_hat dimensionless load
# \return stress distribution factor (Function)
def func_J(inParams, q_hat):
    outfile = open("log.txt", "a")
    print("function func_J called with inputs: {", file=outfile)
    print("  inParams = ", end='', file=outfile)
    print("Instance of InputParameters object", end='', file=outfile)
    print(", ", file=outfile)
    print("  q_hat = ", end='', file=outfile)
    print(q_hat, file=outfile)
    print("  }", file=outfile)
    outfile.close()
    
    return Interpolation.func_interpZ("SDF.txt", inParams.AR, q_hat)

## \brief Calculates non-factored load: three second duration uniform load associated with a probability of breakage less than or equal to 8 lites per 1000 for monolithic AN glass (Pa)
# \param inParams structure holding the input values
# \param q_hat_tol tolerable load
# \return non-factored load: three second duration uniform load associated with a probability of breakage less than or equal to 8 lites per 1000 for monolithic AN glass (Pa)
def func_NFL(inParams, q_hat_tol):
    outfile = open("log.txt", "a")
    print("function func_NFL called with inputs: {", file=outfile)
    print("  inParams = ", end='', file=outfile)
    print("Instance of InputParameters object", end='', file=outfile)
    print(", ", file=outfile)
    print("  q_hat_tol = ", end='', file=outfile)
    print(q_hat_tol, file=outfile)
    print("  }", file=outfile)
    outfile.close()
    
    return q_hat_tol * 7.17e10 * inParams.h ** 4 / (inParams.a * inParams.b) ** 2

## \brief Calculates risk of failure
# \param inParams structure holding the input values
# \param J stress distribution factor (Function)
# \return risk of failure
def func_B(inParams, J):
    outfile = open("log.txt", "a")
    print("function func_B called with inputs: {", file=outfile)
    print("  inParams = ", end='', file=outfile)
    print("Instance of InputParameters object", end='', file=outfile)
    print(", ", file=outfile)
    print("  J = ", end='', file=outfile)
    print(J, file=outfile)
    print("  }", file=outfile)
    outfile.close()
    
    return 2.86e-53 / (inParams.a * inParams.b) ** (7.0 - 1) * (7.17e10 * inParams.h ** 2) ** 7.0 * inParams.LDF * math.exp(J)

## \brief Calculates load resistance: the uniform lateral load that a glass construction can sustain based upon a given probability of breakage and load duration as defined in (pp. 1 and 53) Ref: astm2009 (Pa)
# \param inParams structure holding the input values
# \param NFL non-factored load: three second duration uniform load associated with a probability of breakage less than or equal to 8 lites per 1000 for monolithic AN glass (Pa)
# \return load resistance: the uniform lateral load that a glass construction can sustain based upon a given probability of breakage and load duration as defined in (pp. 1 and 53) Ref: astm2009 (Pa)
def func_LR(inParams, NFL):
    outfile = open("log.txt", "a")
    print("function func_LR called with inputs: {", file=outfile)
    print("  inParams = ", end='', file=outfile)
    print("Instance of InputParameters object", end='', file=outfile)
    print(", ", file=outfile)
    print("  NFL = ", end='', file=outfile)
    print(NFL, file=outfile)
    print("  }", file=outfile)
    outfile.close()
    
    return NFL * inParams.GTF * 1

## \brief Calculates 3 second load equivalent resistance safety requirement
# \param LR load resistance: the uniform lateral load that a glass construction can sustain based upon a given probability of breakage and load duration as defined in (pp. 1 and 53) Ref: astm2009 (Pa)
# \param q applied load (demand): 3 second duration equivalent pressure (Pa)
# \return 3 second load equivalent resistance safety requirement
def func_is_safeLR(LR, q):
    outfile = open("log.txt", "a")
    print("function func_is_safeLR called with inputs: {", file=outfile)
    print("  LR = ", end='', file=outfile)
    print(LR, end='', file=outfile)
    print(", ", file=outfile)
    print("  q = ", end='', file=outfile)
    print(q, file=outfile)
    print("  }", file=outfile)
    outfile.close()
    
    return LR > q

## \brief Calculates probability of breakage: the fraction of glass lites or plies that would break at the first occurrence of a specified load and duration, typically expressed in lites per 1000 (Ref: astm2016)
# \param B risk of failure
# \return probability of breakage: the fraction of glass lites or plies that would break at the first occurrence of a specified load and duration, typically expressed in lites per 1000 (Ref: astm2016)
def func_P_b(B):
    outfile = open("log.txt", "a")
    print("function func_P_b called with inputs: {", file=outfile)
    print("  B = ", end='', file=outfile)
    print(B, file=outfile)
    print("  }", file=outfile)
    outfile.close()
    
    return 1 - math.exp(-B)

## \brief Calculates probability of glass breakage safety requirement
# \param inParams structure holding the input values
# \param P_b probability of breakage: the fraction of glass lites or plies that would break at the first occurrence of a specified load and duration, typically expressed in lites per 1000 (Ref: astm2016)
# \return probability of glass breakage safety requirement
def func_is_safePb(inParams, P_b):
    outfile = open("log.txt", "a")
    print("function func_is_safePb called with inputs: {", file=outfile)
    print("  inParams = ", end='', file=outfile)
    print("Instance of InputParameters object", end='', file=outfile)
    print(", ", file=outfile)
    print("  P_b = ", end='', file=outfile)
    print(P_b, file=outfile)
    print("  }", file=outfile)
    outfile.close()
    
    return P_b < inParams.P_btol
