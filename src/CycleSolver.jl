module CycleSolver
    include("Equations.jl")
    include("States.jl")
    include("Visualization.jl")
    include("Components.jl")
    include("MassFlowManager.jl")
    include("ThermoProperties.jl")
    include("SystemProperties.jl")
    include("CycleProperties.jl")
    include("Hypotheses.jl")

    macro solve(eqs)
        ClearSystem()

        global SystemVars = Any[]
        for i in eqs.args[2:2:end]
            NewEquation(i)
        end
        
        SetupMass()
        
        newValue = true
        while newValue
            newValue = EquationsSolver(unsolvedEquations)

            newValue |= StatesSolver(unsolvedStates)

            newValue |= ManageConditionalEquations(unsolvedConditionalEquation)

            if newValue
                UpdateEquationList(unsolvedEquations)
            elseif length(unsolvedStates) != 0
                solutionFinded = []
                SolverWithHypotheses("", solutionFinded)
                if length(solutionFinded) == 0
                    throw("System cannot be solved")
                end
                newValue = length(solutionFinded) > 0
                for j in solutionFinded
                    eval(Expr(:(=), j[1], j[2]))
                end
            end
        end

        EvaluateStatesMassFlux()
        EvaluateStatesMassFluxFraction()
        EvaluatePropertiesEquations()
        EvaluateFlexHeatProperties()
        
        deletList = Any[]        
        for i in PropsEquations
            if i[2] < 0.0001 && i[1] in [:Qin, :Qout, :Win, :Wout]
                push!(deletList, i[3])
            end            
        end        
        filter!(x -> !(x[3] in deletList), PropsEquations)

        AssignPropertiesToCycle()
        for cycle in SystemCycles  
            CalculateTotalValueOfProperties(cycle)
            CalculateCycleEfficiency(cycle)
        end  

        global System = PropertiesStruct()
        FilterAndAssignPropertiesToSystem()
        DefineRefrigerationSystem()
        CalculateSystemEfficiency()

        EvaluateFindVariables()

        EvaluateImbalance()
    end

    export PrintResults, PrintImbalance, @solve
end