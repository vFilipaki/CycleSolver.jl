SystemComponents = Any[]

function EnergyBalance(inStt, outStt)
    inEq = :($(inStt[1]).m * $(inStt[1]).h)
    for i in inStt[2:end]
        inEq = Expr(:call, :+, inEq, :($i.m * $i.h))
    end
    outEq = :($(outStt[1]).m * $(outStt[1]).h)
    for i in outStt[2:end]
        outEq = Expr(:call, :+, outEq, :($i.m * $i.h))
    end
    NewEquation(Expr(:(=), inEq, outEq))
end

function InsertComponentIntoList(component)
    inStt = eval(component.args[2])
    outStt = eval(component.args[3])
    inStt = Any[i.name for i in inStt]
    outStt = Any[i.name for i in outStt]
    if length(inStt) == 1
        inStt = inStt[1]
    end
    if length(outStt) == 1
        outStt = outStt[1]
    end
    push!(SystemComponents, [ManageComponentTag(string(
        component.args[1], ": ", string(inStt), " >> ", string(outStt))),
        component.args[2], component.args[3]])
end

function EvaluateImbalance()
    totalMassImbalance = 0.0
    totalEnergyImbalance = 0.0
    totalEntropyGeneration = 0.0
    for i in SystemComponents
        inStt, outStt = [eval(i[2]), eval(i[3])]

        massDefined = true

        inSttProps = Any[]
        for i in inStt
            mass = isnothing(i.m) ? i.mFraction : i.m
            massDefined &= !isnothing(i.m)
            push!(inSttProps, [i.name, i.h * mass, mass, i.s * mass])
        end
        
        outSttProps = Any[]
        for i in outStt
            mass = isnothing(i.m) ? i.mFraction : i.m
            massDefined &= !isnothing(i.m)
            push!(outSttProps, [i.name, i.h * mass, mass, i.s * mass])
        end

        props = Any[0.0, 0.0, 0.0, 0.0] # Q q W w

        for f in fieldnames(CycleSolver.PropertiesStruct)
            if f != :n 
                for j in getfield(CycleSolver.System, f)
                    if j.first == i[1]
                        fStrg = string(f)                            
                        value = fStrg[2:end] == "out" ? -j.second : j.second
                        if fStrg[1:1] == "Q"
                            props[1] = value
                        elseif fStrg[1:1] == "q"
                            props[2] = value
                        elseif fStrg[1:1] == "W"
                            props[3] = value
                        elseif fStrg[1:1] == "w"
                            props[4] = value
                        end
        end end end end

        MassImbalance = 0.0
        EnergyImbalance = 0.0
        EntropyGeneration = 0.0

        for i in inSttProps
            MassImbalance += i[3]
            MassImbalance += i[2]
            EntropyGeneration -= i[4]
        end
        for i in outSttProps
            MassImbalance -= i[3]
            MassImbalance -= i[2]
            EntropyGeneration += i[4]
        end

        if massDefined
            MassImbalance += props[1] + props[3]
        else
            MassImbalance += props[2] + props[4]
        end
        
        totalMassImbalance += MassImbalance
        totalEnergyImbalance += EnergyImbalance
        totalEntropyGeneration += EntropyGeneration

        push!(i, [
            inSttProps,
            outSttProps,
            props,
            MassImbalance,
            EnergyImbalance,
            massDefined,
            EntropyGeneration
        ])
    end
    global SystemImbalanceAndEntropyGeneration = [
        totalEnergyImbalance,
        totalMassImbalance,
        totalEntropyGeneration
    ]
end

function GetStatesSymbols(inStt, outStt)
    return [
        Any[i.name for i in inStt],
        Any[i.name for i in outStt]
    ]
end

function generic_component(inStt, outStt, props=nothing)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    MassFlow(Any[inStt[1]], Any[outStt[1]])

    if !isnothing(props)
        for i in props
            push!(PropsEquations, Any[i.args[1], i.args[2],
            [string("generic_component: ", string(inStt), " >> ", string(outStt)), inStt[1]]])    
end end end 

function pump(inStt, outStt, n = 100)
    inStt, outStt = GetStatesSymbols(inStt, outStt)    
    if length(inStt) != length(outStt)
        throw(DomainError("The number of input and output states must be equal in the pump."))
    elseif length(inStt) > 1
        for i in 1:length(inStt)
            pump([eval(inStt[i])], [eval(outStt[i])], n)
        end
        return
    else
        MassFlow(Any[inStt[1]], Any[outStt[1]])
        inStt = inStt[1]
        outStt = outStt[1]
    end
    
    push!(PropsEquations, Any[:Win, 
    :($outStt.m * $outStt.h - $inStt.m * $inStt.h),
    [string("pump: ", string(inStt), " >> ", string(outStt)), inStt]])
    push!(PropsEquations, Any[:win, 
    :($outStt.h - $inStt.h),
    [string("pump: ", string(inStt), " >> ", string(outStt)), inStt]])        
    
    if n == :find
        push!(findVariables, Any[:(($inStt.h - SttTemp_S)/($inStt.h - $outStt.h)),
            eval(inStt), eval(outStt), string("efficiency of [pump: ",
            string(inStt), " >> ", string(outStt),"]"), 1])
        return
    end

    n /= 100
    
    if n == 1
        NewEquation(:($outStt.s = $inStt.s))
    else
        indexProp = length(stAux) + 1       
        createState(Expr(:ref, :stAux, indexProp))        
        push!(fluidEq, [Expr(:ref, :stAux, indexProp), :($(inStt).Cycle.isRefrigerationCycle), :($(inStt).Cycle.fluid)])

        NewEquation(:($(Expr(:ref, :stAux, indexProp)).s = $inStt.s))
        NewEquation(:($(Expr(:ref, :stAux, indexProp)).p = $outStt.p))
        NewEquation(:($outStt.h = $inStt.h - ($inStt.h - $(Expr(:ref, :stAux, indexProp)).h) / $n))
    end
end

function turbine(inStt, outStt, n = 100)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(inStt) != length(outStt)
        if length(inStt) == 1 && 1 < length(outStt)
            Wouttemp = :($(inStt[1]).m * $(inStt[1]).h)
            wouttemp= :($(inStt[1]).mFraction * $(inStt[1]).h)
            for i in outStt
                Wouttemp = Expr(:call, :(-), Wouttemp, :($i.m * $i.h))
                wouttemp = Expr(:call, :(-), wouttemp, :($i.mFraction * $i.h))
            end
            push!(PropsEquations, Any[:Wout, Wouttemp,
            [string("turbine: ", string(inStt), " >> ", string(outStt)), inStt[1]]])
            push!(PropsEquations, Any[:wout, 
            Expr(:call, :(/), wouttemp, :($(inStt[1]).mFraction)),
            [string("turbine: ", string(inStt), " >> ", string(outStt)), inStt[1]]])
        end
    elseif length(inStt) == 1
        push!(PropsEquations, Any[:Wout, 
        :($(inStt[1]).m * $(inStt[1]).h - $(outStt[1]).m * $(outStt[1]).h),
        [string("turbine: ", string(inStt[1]), " >> ", string(outStt[1])), inStt[1]]])
        push!(PropsEquations, Any[:wout, 
        :($(inStt[1]).h - $(outStt[1]).h),
        [string("turbine: ", string(inStt[1]), " >> ", string(outStt[1])), inStt[1]]])
    end
    
    if length(inStt) != length(outStt)
        if length(inStt) == 1 && 1 < length(outStt)

            MassFlow(inStt, outStt)
            n /= 100

            for i in outStt
                if n == 1
                    NewEquation(:($i.s = $(inStt[1]).s))
                else
                    indexProp = length(stAux) + 1       
                    createState(Expr(:ref, :stAux, indexProp))        
                    push!(fluidEq, [Expr(:ref, :stAux, indexProp), :($(inStt[1]).Cycle.isRefrigerationCycle), :($(inStt[1]).Cycle.fluid)])
                    
                    NewEquation(:($(Expr(:ref, :stAux, indexProp)).s = $(inStt[1]).s))
                    NewEquation(:($(Expr(:ref, :stAux, indexProp)).p = $i.p))
                    NewEquation(:($i.h = $(inStt[1]).h - ($(inStt[1]).h - $(Expr(:ref, :stAux, indexProp)).h) * $n))
                end
            end
            return
        else
            # println("ERROR")
        end
    elseif length(inStt) > 1
        for i in 1:length(inStt)
            turbine(Any[eval(inStt[i])], Any[eval(outStt[i])], n)
        end
        return
    else
        MassFlow(Any[inStt[1]], Any[outStt[1]])
        inStt = inStt[1]
        outStt = outStt[1]
    end

    if n == :find
        push!(findVariables, Any[:(($inStt.h - $outStt.h)/($inStt.h - SttTemp_S)),
            eval(inStt), eval(outStt), string("efficiency of [turbine: ",
            string(inStt), " >> ", string(outStt),"]"), 1])
    else
        n /= 100

        if n == 1
            NewEquation(:($outStt.s = $inStt.s))
        else
            indexProp = length(stAux) + 1       
            createState(Expr(:ref, :stAux, indexProp))        
            push!(fluidEq, [Expr(:ref, :stAux, indexProp), :($(inStt).Cycle.isRefrigerationCycle), :($(inStt).Cycle.fluid)])
            
            NewEquation(:($(Expr(:ref, :stAux, indexProp)).s = $inStt.s))
            NewEquation(:($(Expr(:ref, :stAux, indexProp)).p = $outStt.p))
            NewEquation(:($outStt.h = $inStt.h - ($inStt.h - $(Expr(:ref, :stAux, indexProp)).h) * $n))
        end
    end    
end
    
function condenser(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(inStt) != length(outStt)
        MassFlow(inStt, outStt)
        states = [inStt..., outStt...]
        for i in 1:(length(states) - 1)
            NewEquation(:($(states[i]).p = $(states[i + 1]).p))
        end
        NewEquation(:($(states[end]).p = $(states[1]).p))
        for i in outStt
            NewEquation(:($i.Q = 0))
        end

        Qouttemp = :(0)
        qouttemp = :(0)
        for i in inStt
            Qouttemp = Expr(:call, :(+), Qouttemp, :($i.m * $i.h))
            qouttemp = Expr(:call, :(+), qouttemp, :($i.mFraction * $i.h))
        end       
        push!(PropsEquations, Any[:Qout,
        Expr(:call, :(-), Qouttemp, :($(outStt[1]).m * $(outStt[1]).h)),
        [string("condenser: ", string(inStt), " >> ", string(outStt[1])), inStt[1]]])
        push!(PropsEquations, Any[:qout, 
        Expr(:call, :(-), qouttemp, :($(outStt[1]).h)),
        [string("condenser: ", string(inStt), " >> ", string(outStt[1])), inStt[1]]])  

        return
    elseif length(inStt) > 1
        for i in 1:length(inStt)
            condenser([eval(inStt[i])], [eval(outStt[i])])
        end
        return
    else
        MassFlow([inStt[1]], [outStt[1]])
        inStt = inStt[1]
        outStt = outStt[1]

        push!(PropsEquations, Any[:Qout, 
        :($inStt.m * $inStt.h - $outStt.m * $outStt.h),
        [string("condenser: ", string(inStt), " >> ", string(outStt)), inStt]])
        push!(PropsEquations, Any[:qout, 
        :($inStt.h - $outStt.h),
        [string("condenser: ", string(inStt), " >> ", string(outStt)), inStt]])
    end

    NewEquation(:($outStt.p = $inStt.p))
    NewEquation(:($outStt.Q = 0))
end

function boiler(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(inStt) != length(outStt)
        throw(DomainError("The number of input and output states must be equal in the boiler."))
    elseif length(inStt) > 1
        for i in 1:length(inStt)
            boiler([eval(inStt[i])], [eval(outStt[i])])
        end
        return
    else
        MassFlow([inStt[1]], [outStt[1]])
        inStt = inStt[1]
        outStt = outStt[1]
    end

    push!(PropsEquations, Any[:Qin, 
    :($outStt.m * $outStt.h - $inStt.m * $inStt.h),
    [string("boiler: ", string(inStt), " >> ", string(outStt)), inStt]])
    push!(PropsEquations, Any[:qin, 
    :($outStt.h - $inStt.h),
    [string("boiler: ", string(inStt), " >> ", string(outStt)), inStt]])

    NewEquation(:($outStt.p = $inStt.p))
end

function evaporator(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(inStt) != length(outStt)
        throw(DomainError("The number of input and output states must be equal in the evaporator."))
    elseif length(inStt) > 1
        for i in 1:length(inStt)
            evaporator([eval(inStt[i])], [eval(outStt[i])])
        end
        return
    else
        MassFlow([inStt[1]], [outStt[1]])
        inStt = inStt[1]
        outStt = outStt[1]
    end

    push!(PropsEquations, Any[:Qin, 
    :($outStt.m * $outStt.h - $inStt.m * $inStt.h),
    [string("evaporator: ", string(inStt), " >> ", string(outStt)), inStt]])
    push!(PropsEquations, Any[:qin, 
    :($outStt.h - $inStt.h),
    [string("evaporator: ", string(inStt), " >> ", string(outStt)), inStt]])

    NewEquation(:($outStt.Q = 1))
    NewEquation(:($outStt.p = $inStt.p))
end

function evaporator_condenser(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(inStt) != length(outStt) || length(inStt) != 2
        throw(DomainError("The number of input and output states must be equal to 2 in the evaporator_condenser."))
    end
    EnergyBalance(inStt, outStt)
    push!(closedInteractions, inStt)
    for i in 1:length(inStt)
        MassFlow([inStt[i]], [outStt[i]], true)
        NewEquation(:($(outStt[i]).p = $(inStt[i]).p))
    end
    NewEquation(:($(outStt[1]).Q = 1))
    NewEquation(:($(outStt[2]).Q = 0))

    push!(qflex, Any[inStt, outStt,
    string("evaporator_condenser: ", string(inStt), " >> ", string(outStt))])
end

function expansion_valve(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(inStt) != length(outStt)
        throw(DomainError("The number of input and output states must be equal in the expansion_valve."))
    elseif length(inStt) > 1
        for i in 1:length(inStt)
            expansion_valve([eval(inStt[i])], [eval(outStt[i])])
        end
        return
    else
        MassFlow([inStt[1]], [outStt[1]])
        inStt = inStt[1]
        outStt = outStt[1]
    end
    NewEquation(:($outStt.h = $inStt.h))      
end

function flash_chamber(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(inStt) != length(outStt)
        throw(DomainError("The number of input and output states must be equal in the flash_chamber."))
    elseif length(inStt) > 1
        for i in 1:length(inStt)
            flash_chamber([eval(inStt[i])], [eval(outStt[i])])
        end
        return
    else
        MassFlow([inStt[1]], [outStt[1]])
        inStt = inStt[1]
        outStt = outStt[1]
    end
    NewEquation(:($outStt.h = $inStt.h))        
end

function heater_closed(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(inStt) != length(outStt) || length(inStt) != 2
        throw(DomainError("The number of input and output states must be equal to 2 in the heater_closed."))
    end
    EnergyBalance(inStt, outStt)
    push!(closedInteractions, inStt)
    for i in 1:length(inStt)
        MassFlow([inStt[i]], [outStt[i]], true)
        NewEquation(:($(outStt[i]).p = $(inStt[i]).p))
    end
    
    push!(unsolvedConditionalEquation, ConditionalMathEq(
        :($(inStt[1]).h > $(inStt[2]).h), 
        [:($(outStt[1]).Q = 0)],
        [:($(outStt[2]).Q = 0)]))
    for i in 1:(length(outStt) - 1)
        NewEquation(:($(outStt[i]).T = $(outStt[i + 1]).T))
    end
    if length(outStt) > 2
        NewEquation(:($(outStt[end]).T = $(outStt[1]).T))
end end

function heater_open(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(outStt) != 1
        throw(DomainError("The number of output states must be equal to 1 in the heater_open."))
    end
    MassFlow(inStt, outStt)
    EnergyBalance(inStt, outStt)
    states = [inStt..., outStt...]
    for i in 1:(length(states) - 1)
        NewEquation(:($(states[i]).p = $(states[i + 1]).p))
    end
    if length(states) > 2
        NewEquation(:($(states[end]).p = $(states[1]).p))
    end
    NewEquation(:($(outStt[1]).Q = 0))
end

function mix(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    MassFlow(inStt, outStt)
    EnergyBalance(inStt, outStt)
    states = [inStt..., outStt...]
    for i in 1:(length(states) - 1)
        NewEquation(:($(states[i]).p = $(states[i + 1]).p))
    end
    if length(states) > 2
        NewEquation(:($(states[end]).p = $(states[1]).p))
end end

function div(inStt, outStt)
    if length(inStt) != 1
        throw(DomainError("The number of input states must be equal to 1 in the div."))
    end
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    MassFlow(inStt, outStt)
    states = [inStt..., outStt...]
    for i in 1:(length(states) - 1)
        NewEquation(:($(states[i]).p = $(states[i + 1]).p))
        NewEquation(:($(states[i]).h = $(states[i + 1]).h))
    end
    if length(states) > 2
        NewEquation(:($(states[end]).p = $(states[1]).p))
        NewEquation(:($(states[end]).h = $(states[1]).h))
end end

function process_heater(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    MassFlow(inStt, outStt)
    states = [inStt..., outStt...]
    for i in 1:(length(states) - 1)
        NewEquation(:($(states[i]).p = $(states[i + 1]).p))
    end
    if length(states) > 2
        NewEquation(:($(states[end]).p = $(states[1]).p))   
end end

function compressor(inStt, outStt, n = 100)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(inStt) != length(outStt)
        throw(DomainError("The number of input and output states must be equal in the compressor."))
    elseif length(inStt) > 1
        for i in 1:length(inStt)
            compressor([eval(inStt[i])], [eval(outStt[i])], n)
        end
        return
    else
        MassFlow([inStt[1]], [outStt[1]])
        inStt = inStt[1]
        outStt = outStt[1]
    end

    push!(PropsEquations, Any[:Win, 
    :($outStt.m * $outStt.h - $inStt.m * $inStt.h),
    [string("compressor: ", string(inStt), " >> ", string(outStt)), inStt]])
    push!(PropsEquations, Any[:win, 
    :($outStt.h - $inStt.h),
    [string("compressor: ", string(inStt), " >> ", string(outStt)), inStt]])  

    if n == :find
        push!(findVariables, Any[:(($inStt.h - SttTemp_S)/($inStt.h - $outStt.h)),
            eval(inStt), eval(outStt), string("efficiency of [compressor: ",
            string(inStt), " >> ", string(outStt),"]"), 1])
    else
        n /= 100
        if n == 1
            NewEquation(:($outStt.s = $inStt.s))
        else
            indexProp = length(stAux) + 1       
            createState(Expr(:ref, :stAux, indexProp))        
            push!(fluidEq, [Expr(:ref, :stAux, indexProp), :($(inStt).Cycle.isRefrigerationCycle), :($(inStt).Cycle.fluid)])
            
            NewEquation(:($(Expr(:ref, :stAux, indexProp)).s = $inStt.s))
            NewEquation(:($(Expr(:ref, :stAux, indexProp)).p = $outStt.p))
            NewEquation(:($outStt.h = $inStt.h - ($inStt.h - $(Expr(:ref, :stAux, indexProp)).h) / $n))
        end
    end
end

function combustion_chamber(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(inStt) != 1 || length(outStt) != 1
        throw(DomainError("The number of input and output states must be equal to 1 in the combustion_chamber."))
    end
    MassFlow(inStt, outStt)
    inStt = inStt[1]
    outStt = outStt[1]
    NewEquation(:($outStt.p = $inStt.p))

    push!(qflex, Any[[inStt], [outStt],
    string("combustion_chamber: ", string(inStt), " >> ", string(outStt))])     
end

function heater_exchanger(inStt, outStt, effect = nothing, higherCapacityRate = nothing)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(inStt) != length(outStt) || length(inStt) != 2
        throw(DomainError("The number of input and output states must be equal to 2 in the heater_exchanger."))
    end
    push!(closedInteractions, inStt)
    for i in 1:length(inStt)
        MassFlow([inStt[i]], [outStt[i]], true)
        NewEquation(:($(outStt[i]).p = $(inStt[i]).p))
    end
    
    push!(qflex, Any[inStt, outStt,
    string("heater_exchanger: ", string(inStt), " >> ", string(outStt))]) 

    if effect == :find
        EnergyBalance(inStt, outStt)

        indexProp = length(stAux) + 1       
        createState(Expr(:ref, :stAux, indexProp))
        push!(fluidEq, [Expr(:ref, :stAux, indexProp), :($(inStt[2]).Cycle.isRefrigerationCycle), :($(inStt[2]).Cycle.fluid)])
        NewEquation(:($(Expr(:ref, :stAux, indexProp)).T = $(inStt[1]).T))
        NewEquation(:($(Expr(:ref, :stAux, indexProp)).p = $(inStt[2]).p))

        push!(findVariables, Any[:(($(outStt[1]).h - $(inStt[1]).h) /
        (($(inStt[2]).h - $(Expr(:ref, :stAux, indexProp)).h) * 
        ($(inStt[2]).m / $(inStt[1]).m))),
        string("effectiveness of [heater_exchanger: ",
        string(inStt), " >> ", string(outStt),"]"), nothing, nothing, 2])
        
        return
    end

    if !isnothing(effect) && length(inStt) == 2 && length(outStt) == 2   
        
        indexProp = length(stAux) + 1       
        createState(Expr(:ref, :stAux, indexProp))        
        push!(fluidEq, [Expr(:ref, :stAux, indexProp), :($(inStt[2]).Cycle.isRefrigerationCycle), :($(inStt[2]).Cycle.fluid)])
        NewEquation(:($(Expr(:ref, :stAux, indexProp)).T = $(inStt[1]).T))
        NewEquation(:($(Expr(:ref, :stAux, indexProp)).p = $(inStt[2]).p))

        indexProp2 = length(stAux) + 1       
        createState(Expr(:ref, :stAux, indexProp2))        
        push!(fluidEq, [Expr(:ref, :stAux, indexProp2), :($(inStt[1]).Cycle.isRefrigerationCycle), :($(inStt[1]).Cycle.fluid)])
        NewEquation(:($(Expr(:ref, :stAux, indexProp2)).T = $(inStt[2]).T))
        NewEquation(:($(Expr(:ref, :stAux, indexProp2)).p = $(inStt[1]).p))

        effect /= 100                     

        conditionEq = nothing
        if isnothing(higherCapacityRate)
            conditionEq = :(abs($(outStt[2]).h - $(inStt[2]).h) * $(inStt[2]).m > abs($(outStt[1]).h - $(inStt[1]).h) * $(inStt[1]).m)
        else
            conditionEq = higherCapacityRate == 2
        end

        push!(unsolvedConditionalEquation, ConditionalMathEq(
            conditionEq, 
            [
                :($(outStt[1]).h = $(inStt[1]).h + ($(inStt[2]).m / $(inStt[1]).m) * $effect *
                    ($(inStt[2]).h - $(Expr(:ref, :stAux, indexProp)).h)),
                :($(outStt[2]).h = $(inStt[2]).h - $effect *
                    ($(inStt[2]).h - $(Expr(:ref, :stAux, indexProp)).h))
            ],
            [
                :($(outStt[2]).h = $(inStt[2]).h + ($(inStt[1]).m / $(inStt[2]).m) * $effect *
                    ($(inStt[1]).h - $(Expr(:ref, :stAux, indexProp2)).h)),
                :($(outStt[1]).h = $(inStt[1]).h - $effect *
                    ($(inStt[1]).h - $(Expr(:ref, :stAux, indexProp2)).h))
            ]))
    else
        EnergyBalance(inStt, outStt)
    end
end

function separator(inStt, outStt)
    inStt, outStt = GetStatesSymbols(inStt, outStt)
    if length(outStt) != 2 || length(inStt) != 1
        throw(DomainError("The number of input states must be equal to 1, and the output states must be equal to 2 in the separator."))
    end
    MassFlow(inStt, outStt)
    states = [inStt..., outStt...]
    for i in 1:(length(states) - 1)
        NewEquation(:($(states[i]).p = $(states[i + 1]).p))
    end
    if length(states) > 2
        NewEquation(:($(states[end]).p = $(states[1]).p))
    end
    NewEquation(:($(outStt[1]).Q = 1))
    NewEquation(:($(outStt[2]).Q = 0))
    NewEquation(:($(outStt[1]).m = $(inStt[1]).Q * $(inStt[1]).m))
    NewEquation(:($(outStt[2]).m = $(inStt[1]).m - $(outStt[1]).m))        
end