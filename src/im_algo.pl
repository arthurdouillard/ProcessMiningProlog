clearall :-
    retractall(visited(_)),
    retractall(node(_, _, _)),
    retractall(neg_node(_, _, _)),
    retractall(loop_node(_, _, _)).

:- dynamic (visited/1, node/3, neg_node/3, loop_node/3), clearall.

%-----------------------------------------------------------------------------
% Misc functions.
%--

% Check if the element exist
member(X, [X|_]).
member(X, [_|R]) :-
  member(X, R).

% Add an element if not in the list.
unique_add(X, L, L) :-
  member(X, L).
unique_add(X, L, [X|L]).

% Append to list and remove duplicate.
append_list([], [], []).
append_list([], [X|L2], L) :-
  append_list([], L2, R),
  unique_add(X, R, L).
append_list([X|L1], L2, L) :-
  append_list(L1, L2, R),
  unique_add(X, R, L).

% Create alphabet
create_alphabet_sub([], []).
create_alphabet_sub([X|L], [X|A]) :-
  create_alphabet_sub(L, A).
create_alphabet([], []).
create_alphabet([L|R], A) :-
  create_alphabet_sub(L, Ret_L),
  create_alphabet(R, Ret_R),
  append_list(Ret_L, Ret_R, A).

%=============================================================================
% Inductive Mining algorithm
%==

%-----------------------------------------------------------------------------
% Generates a list representing a graph node, its inputs and outputs 
% i.e a list has the form [[x], [a], [b, c]] where x is the node
% and a the input and b, c are the direct children 
%--

state_inputs_sub([], _, []).
state_inputs_sub([X, State|Log], State, [X|Res]) :-
    state_inputs_sub(Log, State, Res).
state_inputs_sub([_|Log], State, Res) :-
    state_inputs_sub(Log, State, Res).

state_inputs([], _, []).
state_inputs([L|Logs], State, T) :-
    member(State, L),
    state_inputs_sub(L, State, L1),
    !,
    state_inputs(Logs, State, L2),
    append_list(L1, L2, T).
state_inputs([_|Logs], State, T) :-
    state_inputs(Logs, State, T).

state_outputs_sub([], _, []).
state_outputs_sub([State, X|Log], State, [X|Res]) :-
    state_outputs_sub(Log, State, Res).
state_outputs_sub([_|Log], State, Res) :-
    state_outputs_sub(Log, State, Res).

state_outputs([], _, []).
state_outputs([L|Logs], State, T) :-
    member(State, L),
    state_outputs_sub(L, State, L1),
    state_outputs(Logs, State, L2),
    append_list(L1, L2, T).
state_outputs([_|Logs], State, T) :-
    state_outputs(Logs, State, T).

generate_graph_sub(_, [], []).
generate_graph_sub(Logs, [S|States], Graph) :-
    state_inputs(Logs, S, In),
    state_outputs(Logs, S, Out),
    generate_graph_sub(Logs, States, Res),
    append_list([[[S], In, Out]], Res, Graph).

generate_graph(Logs, States, Graph) :-
    generate_graph_sub(Logs, States, Graph).

%-----------------------------------------------------------------------------
% Gets a graph's start and end activities
%--
activities_sub(_, _, [], []).
activities_sub('start', Graph, [Elt|Clique], [Elt|Res]) :-
    node(Elt, In, _),
    (\+ subset(In, Graph); length(In, 0)),
    activities_sub('start', Graph, Clique, Res).
activities_sub('end', Graph, [Elt|Clique], [Elt|Res]) :-
    node(Elt, _, Out),
    \+ subset(Out, Graph),
    activities_sub('end', Graph, Clique, Res).
activities_sub(Type, Graph, [_|Clique], Res) :-
    activities_sub(Type, Graph, Clique, Res).

activities(_, _, [], []).
activities(Type, Base, [G|Graph], Activities) :-
    flatten(Base, FlatBase),
    activities_sub(Type, FlatBase, G, L1),
    activities(Type, FlatBase, Graph, L2),
    append(L1, L2, Activities).

%-----------------------------------------------------------------------------
% Adds a node into the database.
% The node has the form [[x], [a, b], [c, d]] with a,b the inputs
% and c,d the outputs 
%--

add_nodes([], _).
add_nodes([Clique|Graph], Method) :-
    unpack_node(Clique, State, In, Out),
    select(Val, State, []),
    Pred =.. [Method, Val, In, Out],
    assert(Pred),
    add_nodes(Graph, Method).

create_database(Graph) :-
    add_nodes(Graph, node).
%-----------------------------------------------------------------------------
% Retrieves a node and its inputs/ouputs from the graph
%--

unpack_node([S, Ins, Outs], [Clique], Ins, Outs) :-
    select(Clique, S, []).

%-----------------------------------------------------------------------------
% Orders the graph using a DFS 
%--

get_start([], []).
get_start([G|Graph], [Activity|Start]) :-
    unpack_node(G, A, In, _),
    select(Activity, A, []),
    length(In, 0),
    get_start(Graph, Start).
get_start([_|Graph], Start) :-
    get_start(Graph, Start).

dfs([], []).
dfs([N|Queue], [N|Res]) :-
    unpack_node(N, Val, _, Out),
    select(X, Val, []),
    \+ visited(X),
    assert(visited(X)),
    full_graph_sub(Out, OutGraph),
    append_list(Queue, OutGraph, NewQueue),
    dfs(NewQueue, Res).
dfs([_|Queue], Res) :-
    dfs(Queue, Res).

order_graph(Graph, OrderedGraph) :-
    get_start(Graph, Root),
    select(A, Root, []),
    node(A, In, Out),
    dfs([[Root, In, Out]], OrderedGraph),
    retractall(visited(_)).


%-----------------------------------------------------------------------------
% Generate singleton trees from the graph 
%--
generate_trees([], []).
generate_trees([Clique|Graph], [Val|Res]) :-
    unpack_node(Clique, Val, _, _),
    generate_trees(Graph, Res).

%=============================================================================
% CUT ALGORITHMS
%==

%-----------------------------------------------------------------------------
% Set of functions performing a BASE CUT. 
% This is technically not a cut. 
% Detects graphs with a single activity left, i.e [a]
%--

base_cut(Graph, Base) :-
    flatten(Graph, Flat),
    length(Flat, 1),
    select(Base, Flat, []).

%-----------------------------------------------------------------------------
% Set of functions performing a SEQUENTIAL CUT. 
% First step is to find the connected components.
% Second step is to merge the unreachable pairwise components.
% Fails if there a no changes (No cuts were found)
%--

% Returns true if A and B are in the same strongly connected component
ssc(A, B) :-
    retractall(visited(_)),
    path(A, B, node),
    !,
    retractall(visited(_)),
    path(B, A, node).

% Returns true if A and B are not connected
not_connected(A, B) :-
    retractall(visited(_)),
    \+ path(A, B, node),
    retractall(visited(_)),
    \+ path(B, A, node).

% Returns true if there's at least one connection between A and B
connected(A, B, Caller) :-
    retractall(visited(_)),
    path(A, B, Caller).
connected(A, B, Caller) :-
    retractall(visited(_)),
    path(B, A, Caller).

%---
% Path looks for a path between two graphs 
% The graphs are lists which contains one or many nodes 
% i.e [a, b] and [c, d, e]
%--

%-- STEP 1
% Gets the nodes from the graphs
path_rec(A, [X|_], Caller) :-
    path(A, X, Caller).
path_rec(A, [_|T], Caller) :-
    path_rec(A, T, Caller).
path_rec([Nd|_], Target, Caller) :-
    path(Nd, Target, Caller).
path_rec([_|Clique], Target, Caller) :-
    path_rec(Clique, Target, Caller).

% Calls path on the node's children
path_sub(_, Target, [O|_], Caller) :-
    path([O], Target, Caller).
path_sub(A, Target, [_|Out], Caller) :-
    path_sub(A, Target, Out, Caller).

% Visits a node and marks it.
% Then calls path_sub on its children
path(A, A, _) :-
    assert(visited(A)).
path([Nd|Clique], Target, Caller) :-
    path_rec([Nd|Clique], Target, Caller).
path(A, [X|Target], Caller) :-
    path_rec(A, [X|Target], Caller).
path(A, Target, Caller) :-
    \+ is_list(A),
    \+ is_list(Target),
    \+ visited(A),
    assert(visited(A)),
    call(Caller, A, _, Out),
    path_sub(A, Target, Out, Caller).

% Returns the strongly connected component
% containing the node A
connected_components(C, [], C).
connected_components(A, [B|Graph], Clique) :-
    ssc(A, B),
    append(A, B, C),
    connected_components(C, Graph, Clique).
connected_components(A, [_|Graph], Clique) :-
    connected_components(A, Graph, Clique).

% Removes the nodes merged into a clique
% from the main graph
remove_nodes(_, [], []).
remove_nodes(Clique, [X1|G1], G2) :-
    intersection(Clique, X1, X2),
    \+ length(X2, 0),
    remove_nodes(Clique, G1, G2).
remove_nodes(Clique, [X|G1], [X|G2]) :-
    remove_nodes(Clique, G1, G2).

sequential_cut_sub([], []).
sequential_cut_sub([A|G1], [Clique|Components]) :-
    connected_components(A, G1, Clique),
    remove_nodes(Clique, G1, G2),
    sequential_cut_sub(G2, Components).

%-- STEP 2
% Merges unreachable pairwise components
merge_graphs_sub(C, [], C).
merge_graphs_sub(Tree, [X|Graph], NewTree) :-
    not_connected(Tree, X),
    append(Tree, X, TempTree),
    merge_graphs_sub(TempTree, Graph, NewTree).
merge_graphs_sub(Tree, [_|Graph], NewTree) :-
    merge_graphs_sub(Tree, Graph, NewTree).

merge_graphs([], []).
merge_graphs([T|SubTrees], [G|NewGraphs]) :-
    merge_graphs_sub(T, SubTrees, G),
    remove_nodes(G, SubTrees, Res),
    merge_graphs(Res, NewGraphs).

% Finds the ssc (strongly connected components)
% then merges the ssc's which are not connected at all
sequential_cut(Graph, seq, NewGraphs) :-
    sequential_cut_sub(Graph, SubTrees),
    merge_graphs(SubTrees, NewGraphs),
    NewGraphs \= Graph.

%-----------------------------------------------------------------------------
% Set of functions performing an EXCLUSIVE CUT. 
% Within a graph of the form [a, b, c, d], finds the sscs so that the result is
% in the form [[a, b], [c, d]]
% Fails if there a no changes (No cuts were found)
%--

divide_node_sub(_, [], []).
divide_node_sub(Elt, [X|L], [X|Res]) :-
    ssc(Elt, X),
    divide_node_sub(Elt, L, Res).
divide_node_sub(Elt, [_|X], Res) :-
    divide_node_sub(Elt, X, Res).

divide_node([], []).
divide_node([Elt|L1], [Res|NewGraph]) :-
    divide_node_sub(Elt, L1, Tmp),
    append([Elt], Tmp, Res), % Append Elt to head of list to keep the order
    subtract(L1, Res, L2),
    divide_node(L2, NewGraph).

exclusive_cut_sub([], []).
exclusive_cut_sub([G|Graph], NewGraphs) :-
    divide_node(G, G1),
    exclusive_cut_sub(Graph, G2),
    append(G1, G2, NewGraphs).

exclusive_cut(Graph, alt, NewGraphs) :-
    exclusive_cut_sub(Graph, NewGraphs),
    !,
    NewGraphs \= Graph.

%-----------------------------------------------------------------------------
% Set of functions performing a CONCURRENT CUT. 
% First negates the graph
% Secondly, computes the concurrent activities by taking the connected components
% The parallel activities are the connected components
% Fails if there a no changes (No cuts were found)
%--

% Returns the full graph from the graph passed as parameter
% i.e for each node, we get the input and output nodes
% For instance, [a] becomes [[a], [], [b, c]] with b and c the outputs
full_graph_sub([], []).
full_graph_sub([N|Cliques], [[[N], In, Out]|Res]) :-
    node(N, In, Out),
    full_graph_sub(Cliques, Res).

full_graph([], []).
full_graph([G|Graph], Res) :-
    full_graph_sub(G, L1),
    full_graph(Graph, L2),
    append(L1, L2, Res).

% For each node, switches the inputs and the ouputs
% If the node contains an element x in both the input and ouput sets
% x is removed from both sets
negate_states_sub(In, Out, NewIn, NewOut) :-
    intersection(In, Out, Intersect),
    \+ length(Intersect, 0),
    subtract(In, Intersect, NewIn),
    subtract(Out, Intersect, NewOut).
negate_states_sub(In, Out, In, Out).

negate_states([], []).
negate_states([G|Graph], [[A, NewOut, NewIn]|NegGraph]) :-
    unpack_node(G, A, In, Out),
    negate_states_sub(In, Out, NewIn, NewOut),
    negate_states(Graph, NegGraph).

% Computes the negated graph and saves it into the database
negate_graph(Graph, NegGraph) :-
    full_graph(Graph, Full),
    negate_states(Full, NegGraph),
    add_nodes(NegGraph, neg_node).

% Removes an element from the full graph
% for instance, if A = [a], removes the node [[a], [x], [x]]
% from the graph 
remove_elt(_, [], []).
remove_elt(A, [G|Graph], Res) :-
    unpack_node(G, B, _, _),
    subset(B, A),
    remove_elt(A, Graph, Res).
remove_elt(A, [G|Graph], [G|Res]) :-
    remove_elt(A, Graph, Res).

% Computes the parallel sets in the graph
% The parallel sets are the connected components of negated graph
parallel_components(C, [], C).
parallel_components(A, [G|Graph], Res) :-
    unpack_node(G, B, _, _),
    connected(A, B, neg_node),
    append(A, B, C),
    parallel_components(C, Graph, Res).
parallel_components(A, [_|Graph], Res) :-
    parallel_components(A, Graph, Res).

parallel_cut_sub([], []).
parallel_cut_sub([G|Graph], [C|NewGraphs]) :-
    unpack_node(G, A, _, _),
    parallel_components(A, Graph, C),
    remove_elt(C, Graph, GraphBis),
    parallel_cut_sub(GraphBis, NewGraphs).

% The parallel cut is valid if for each cluster :
% The intersection between the cluster and the start set is not empty
% The intersection between the cluster and the end set is not empty
is_parallel([], _, _).
is_parallel([G|Graph], Start, End) :-
    intersection(Start, G, StartIntersect),
    \+ length(StartIntersect, 0),
    intersection(End, G, EndIntersect),
    \+ length(EndIntersect, 0),
    is_parallel(Graph, Start, End).

% Negates the graph and computes the parallel components
parallel_cut(Graph, par, NewGraphs) :-
    activities('start', Graph, Graph, Start),
    activities('end', Graph, Graph, End),
    negate_graph(Graph, NegGraph),
    parallel_cut_sub(NegGraph, NewGraphs),
    !,
    is_parallel(NewGraphs, Start, End),
    retractall(neg_node(_, _, _)),
    NewGraphs \= Graph.

%-----------------------------------------------------------------------------
% Set of functions performing a LOOP CUT. 
% First, the connected components of the graph are computed by removing the
% start and end states. 
% Then, each component is examined to determine whether it goes from
% the start states to the end states (Body component) or the other way
% around (Redo component).
%--

% Removes the loop body from the full_graph's transitions
remove_transitions(_, [], []).
remove_transitions(Body, [G|Graph], [[A, NewIn, NewOut]|Res]) :-
    unpack_node(G, A, In, Out),
    subtract(In, Body, NewIn),
    subtract(Out, Body, NewOut),
    remove_transitions(Body, Graph, Res).

% Removes the loop body from the graph
remove_body(_, [], []).
remove_body(Body, [G1|Graph], [G2|Res]) :-
    subtract(G1, Body, G2),
    remove_body(Body, Graph, Res).

% Puts a graph in the form [[a], [b,c]] to the form
% [[a], [b], [c]]
deconstruct_graph([], []).
deconstruct_graph([G|Graph], [A|Res]) :-
    unpack_node(G, A, _, _),
    deconstruct_graph(Graph, Res).

% Regroups the loop activities into clusters
% Those clusters will join the body or will be part of the redo.
loop_components(CC, [], CC).
loop_components(A, [G|Graph], Res) :-
    connected(A, G, loop_node),
    append(A, G, CC),
    loop_components(CC, Graph, Res).
loop_components(A, [_|Graph], Res) :-
    loop_components(A, Graph, Res).

% loop_cc computes the loop's connected components
% by getting the start & end activities of the loop
% and removing them from the graph

% Computes the loops connected components
% from the graph without the start & end states
loop_cc_sub([], []).
loop_cc_sub([A|Graph], [Res|CC]) :-
    loop_components(A, Graph, Res),
    remove_nodes(Res, Graph, G1),
    loop_cc_sub(G1, CC).

loop_cc(Graph, Start, End, CC) :-
    activities('start', Graph, Graph, Start), % Gets start activities
    activities('end', Graph, Graph, End),
    append_list(Start, End, TempBody),
    remove_body(TempBody, Graph, Res), % Removes Start & End activities
    full_graph(Res, FullGraph),
    remove_transitions(TempBody, FullGraph, ReducedGraph),
    add_nodes(ReducedGraph, loop_node),
    deconstruct_graph(ReducedGraph, Deconstructed),
    loop_cc_sub(Deconstructed, CC).

% Returns the path just inserted in the database
retrieve_path([X|Res]) :-
    retract(visited(X)),
    retrieve_path(Res).
retrieve_path([]).

% C is part of the loop body if it reaches the start states
% by going through at least one end state
is_body(C, Start, End) :-
    retractall(visited(_)),
    path(C, Start, node),
    retrieve_path(Path),
    !,
    intersection(Path, End, Res),
    \+ length(Res, 0).

% C is part of the loop redo if it reaches the end states
% by going through at least one start state
is_redo(C, Start, End) :-
    retractall(visited(_)),
    path(C, End, node),
    retrieve_path(Path),
    !,
    intersection(Path, Start, Res),
    \+ length(Res, 0).

% Tells whether an activity is the body part of the loop
% or the redo part
body_redo([], _, _, [], []).
body_redo([C|Component], Start, End, [C|Body], Redo) :-
    is_body(C, Start, End),
    body_redo(Component, Start, End, Body, Redo).
body_redo([C|Component], Start, End, Body, [C|Redo]) :-
    is_redo(C, Start, End),
    body_redo(Component, Start, End, Body, Redo).

% Takes the loop's connected components and adds them either
% to the Body cluster or to the Redo cluster
reachability(Components, Start, End, [Body, Redo]) :-
    body_redo(Components, Start, End, TempBody, TempRedo),
    flatten(TempBody, FlatBody),
    flatten(TempRedo, Redo),
    \+ length(Redo, 0), % If no redo, we must use the second clause
    append_list(Start, FlatBody, B1),
    append_list(B1, End, Body).

reachability(Components, Start, End, [Body]) :-
    body_redo(Components, Start, End, TempBody, _),
    flatten(TempBody, FlatBody),
    append_list(Start, FlatBody, B1),
    append_list(B1, End, Body).

loop_cut_sub(Graph, NewGraphs) :-
    loop_cc(Graph, Start, End, Components),
    reachability(Components, Start, End, NewGraphs).

loop_cut(Graph, loop, NewGraphs) :-
    loop_cut_sub(Graph, NewGraphs),
    !,
    NewGraphs \= Graph.

%=============================================================================
% imd is the main_algorithm 
% first, it looks for a base case for the graph, if not found, 
% it tries different cut methods
%==

% Find cut tries to split the graph according to the four operators
find_cut(Graph, Operator, NewGraphs) :-
    exclusive_cut(Graph, Operator, NewGraphs).
find_cut(Graph, Operator, NewGraphs) :-
    sequential_cut(Graph, Operator, NewGraphs).
find_cut(Graph, Operator, NewGraphs) :-
    parallel_cut(Graph, Operator, NewGraphs).
find_cut(Graph, Operator, NewGraphs) :-
    loop_cut(Graph, Operator, NewGraphs).

% Splits transforms sets from the cuts into graphs,
% i.e  [b, c, d, e] becomes [[b, c, d, e]]
split([], []).
split([C|Cuts], [[C]|Res]) :-
    split(Cuts, Res).

% Calls imd on all the subgraphs generated by the cuts
imd_sub([], []).
imd_sub([G|Graph], [SubGraph|Res]) :-
    imd(G, SubGraph),
    imd_sub(Graph, Res).

imd(Graph, Script) :-
    base_cut(Graph, Script).
imd(Graph, Script) :-
    find_cut(Graph, Operator, Cuts),
    split(Cuts, SubGraphs),
    imd_sub(SubGraphs, NewGraphs),
    Script =.. [Operator, NewGraphs].
imd(Graph, Script) :- % No cuts -> Returns a loop (as in the paper) 
    flatten(Graph, FlatGraph),
    Script =.. [loop, FlatGraph].

test1 :-
    Logs=[[a, b, c, f, g, h, i], [a, b, c, g, h, f, i], [a, b, c, h, f, g, i],
          [a, c, b, f, g, h, i], [a, c, b, g, h, f, i], [a, c, b, h, f, g, i],
          [a, d, f, g, h, i], [a, d, e, d, g, h, f, i], [a, d, e, d, e, d, h, f, g, i]],
    create_alphabet(Logs, States),
    generate_graph(Logs, States, Graph),
    create_database(Graph),
    order_graph(Graph, OrderedGraph),
    generate_trees(OrderedGraph, Trees),
    imd(Trees, _).

test2 :-
    Logs=[[a, b, c, d], [a, c, b, d]], 
    create_alphabet(Logs, States),
    generate_graph(Logs, States, Graph),
    create_database(Graph),
    order_graph(Graph, OrderedGraph),
    generate_trees(OrderedGraph, Trees),
    imd(Trees, _).

testloop :-
    Logs=[[a, b, c, d, e, f, b, c, d, e, h]],
    create_alphabet(Logs, States),
    generate_graph(Logs, States, Graph),
    create_database(Graph),
    order_graph(Graph, OrderedGraph),
    generate_trees(OrderedGraph, Trees),
    imd(Trees, _).