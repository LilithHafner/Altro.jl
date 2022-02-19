using Altro
using TrajectoryOptimization
using Test
using StaticArrays
using ForwardDiff
using RobotDynamics
using LinearAlgebra
using RobotZoo
using SolverLogging
const RD = RobotDynamics
const TO = TrajectoryOptimization

prob, opts = Problems.Pendulum()

al1 = Altro.AugmentedLagrangianSolver(prob, copy(opts))
al2 = Altro.ALSolver(prob, copy(opts))

@test states(al1) ≈ states(al2)
@test controls(al1) ≈ controls(al2)

# Check unconstrained cost
@test cost(get_objective(al1).obj, prob.Z) ≈ cost(get_objective(al2).obj, prob.Z)

# Check constrained cost
@test max_violation(al1) ≈ TO.max_violation(al2)
@test cost(al1) ≈ cost(al2)

obj2 = get_objective(al2)
obj2.obj[1].q

# Check iLQR solves
ilqr1 = Altro.get_ilqr(al1)
ilqr2 = Altro.get_ilqr(al2)
@test cost(ilqr1) ≈ cost(ilqr2)

conset1 = get_constraints(al1)
conset2 = get_constraints(al2)
Z1 = get_trajectory(al1)
Z2 = get_trajectory(al2)

# Check constraint values
# These have already been evaluated by the cost
for i = 1:length(conset2) 
    @test conset1.convals[i].vals ≈ conset2[i].vals
end

# Test unconstrained cost expansion
TO.cost_expansion!(ilqr1.quad_obj, ilqr1.obj.obj, ilqr1.Z, init=true, rezero=true)
Altro.cost_expansion!(ilqr2.obj.obj, ilqr2.Efull, ilqr2.Z)
for k = 1:prob.N
    @test ilqr1.quad_obj[k].hess ≈ ilqr2.Efull[k].hess
    @test ilqr1.quad_obj[k].grad ≈ ilqr2.Efull[k].grad
end

# Test full cost expansion
TO.cost_expansion!(ilqr1.quad_obj, ilqr1.obj, ilqr1.Z, init=true, rezero=true)
Altro.cost_expansion!(ilqr2.obj, ilqr2.Efull, ilqr2.Z)

# Check constraint Jacobians and AL penalty cost expansion
for i = 1:length(conset2)
    @test conset1.convals[i].jac ≈ conset2[i].jac
    @test conset1.convals[i].grad ≈ conset2[i].grad
    @test conset1.convals[i].hess ≈ conset2[i].hess
end
for k = 1:prob.N
    @test ilqr1.quad_obj[k].hess ≈ ilqr2.Efull[k].hess
    @test ilqr1.quad_obj[k].grad ≈ ilqr2.Efull[k].grad
end

ilqr1.opts.verbose = 0
ilqr2.opts.verbose = 0
for i = 1:4
    solve!(ilqr1)
    solve!(ilqr2)
    Altro.dual_update!(al1)
    Altro.dualupdate!(conset2)
    Altro.penalty_update!(conset1)
    Altro.penaltyupdate!(conset2)
end


## Call iLQR complete solve
lg = Altro.getlogger(ilqr2)
ilqr1.opts.verbose = 2
ilqr2.opts.verbose = 4
solve!(ilqr1)
printheader(lg)
solve!(ilqr2)

s1 = ilqr1
s2 = ilqr2

@test iterations(ilqr1) ≈ iterations(ilqr2)
@test cost(ilqr1) ≈ cost(ilqr2)
@test max_violation(al1) ≈ max_violation(al2)

# Update duals and penalties
Altro.dual_update!(al1)
Altro.dualupdate!(conset2)
for i = 1:length(conset2)
    @test conset1.convals[i].λ ≈ conset2[i].λ
end

Altro.penalty_update!(conset1)
Altro.penaltyupdate!(conset2)
for i = 1:length(conset2)
    @test conset1.convals[i].μ ≈ conset2[i].μ
end

## Try solving the entire problem
prob, opts = Problems.Pendulum()
prob, opts = Problems.DubinsCar(:turn90, N=11)

s1 = Altro.iLQRSolver(prob, opts)
s2 = Altro.iLQRSolver2(prob, opts)

al1.opts.verbose = 0
al2.opts.verbose = 0
solve!(s1)
solve!(s2)