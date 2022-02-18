"""$(TYPEDEF)
Augmented Lagrangian Trajectory Optimizer (ALTRO) is a solver developed by the Robotic Exploration Lab at Stanford University.
    The solver is special-cased to solve Markov Decision Processes by leveraging the internal problem structure.

ALTRO consists of two "phases":
1) AL-iLQR: iLQR is used with an Augmented Lagrangian framework to solve the problem quickly to rough constraint satisfaction
2) Projected Newton: A collocation-flavored active-set solver projects the solution from AL-iLQR onto the feasible subspace to achieve machine-precision constraint satisfaction.

# Constructor

    ALTROSolver(prob::Problem, opts::SolverOptions; [infeasible, R_inf, kwarg_opts...])

The `infeasible` keyword is a boolean flag that specifies whether the solver should
augment the controls to make it artificially fully actuated, allowing state initialization.
The `R_inf` is the weight on these augmented controls. Any solver options can be passed
as additional keyword arguments and will be set in the solver.

# Getters
* `get_model`
* `get_objective`
* `get_constraints`
* `Altro.get_ilqr`
* `TO.get_initial_state`

# Other methods
* `Base.size`: returns `(n,m,N)`
* `TO.is_constrained`
"""
struct ALTROSolver2{T,S} <: ConstrainedSolver{T}
    opts::SolverOptions{T}
    stats::SolverStats{T}
    solver_al::ALSolver{T,S}
    solver_pn::ProjectedNewtonSolver{Nx,Nu,Nxu,T} where {Nx,Nu,Nxu}
end

function ALTROSolver2(prob::Problem{T}, opts::SolverOptions=SolverOptions();
        infeasible::Bool=false,
        R_inf::Real=1.0,
        kwarg_opts...
    ) where {Q,T}
    if infeasible
        # Convert to an infeasible problem
        prob = InfeasibleProblem(prob, prob.Z, R_inf)

        # Set infeasible constraint parameters
        # con_inf = get_constraints(prob).constraints[end]
        # con_inf::ConstraintVals{T,Control,<:InfeasibleConstraint}
        # con_inf.params.μ0 = opts.penalty_initial_infeasible
        # con_inf.params.ϕ = opts.penalty_scaling_infeasible
    end
    set_options!(opts; kwarg_opts...)
    stats = SolverStats{T}(parent=solvername(ALTROSolver))
    solver_al = ALSolver(prob, opts, stats)
    solver_pn = ProjectedNewtonSolver(prob, opts, stats)
    # link_constraints!(get_constraints(solver_pn), get_constraints(solver_al))
    S = typeof(solver_al.ilqr)
    solver = ALTROSolver2{T,S}(opts, stats, solver_al, solver_pn)
    reset!(solver)
    # set_options!(solver; opts...)
    solver
end


# Getters
get_ilqr(solver::ALTROSolver2) = get_ilqr(solver.solver_al)
for method in (:(RD.dims), :(RD.state_dim), :(RD.errstate_dim), :(RD.control_dim), 
              :(TO.get_trajectory), :(TO.get_objective), :(TO.get_model), 
              :(TO.get_initial_state), :getlogger)
    @eval $method(solver::ALTROSolver2) = $method(get_ilqr(solver))
end
TO.get_constraints(solver::ALTROSolver2) = get_constraints(solver.solver_al)
stats(solver::ALTROSolver2) = solver.stats
options(solver::ALTROSolver2) = solver.opts

is_constrained(solver::ALTROSolver2) = !isempty(get_constraints(solver.solver_al))
solvername(::Type{<:ALTROSolver2}) = :ALTRO

# Methods
