licenses(["notice"])

package(
    default_visibility = ["//visibility:public"],
)

cc_library(
    name = "AbboudMISrFeasibility",
    hdrs = ["AbboudMISrFeasibility.h"],
    deps = [
        "//benchmarks/BFS/BFSdist:BFSdistRepair",
        "//benchmarks/BFS/BFSdist:BFSdistRepairSeq",

        "//benchmarks/PositiveWeightSSSP/DeltaStepping:DeltaSteppingRepair",
        "//benchmarks/PositiveWeightSSSP/Dijkstra:DijkstraRepair",

        "//gbbs",
        "@parlaylib//parlay:primitives",
        "@parlaylib//parlay:random",
        "@parlaylib//parlay:sequence",
    ],
)

cc_binary(
    name = "AbboudMISrFeasibility_main",
    srcs = ["AbboudMISrFeasibility.cc"],
    deps = [
        ":AbboudMISrFeasibility",
        "//benchmarks/Clustering/K-Center/common:DispatchMain",
    ],
)

cc_library(
    name = "AbboudMISr",
    hdrs = ["AbboudMISr.h"],
    deps = [
        ":AbboudMISrFeasibility",

        "//benchmarks/BFS/BFSdist:BFSdistRepair",
        "//benchmarks/BFS/BFSdist:BFSdistRepairSeq",

        "//benchmarks/PositiveWeightSSSP/DeltaStepping:DeltaSteppingRepair",
        "//benchmarks/PositiveWeightSSSP/Dijkstra:DijkstraRepair",

        "//gbbs",
        "@parlaylib//parlay:primitives",
        "@parlaylib//parlay:random",
        "@parlaylib//parlay:sequence",
    ],
)

cc_binary(
    name = "AbboudMISr_main",
    srcs = ["AbboudMISr.cc"],
    deps = [
        ":AbboudMISr",
        "//benchmarks/Clustering/K-Center/common:DispatchMain",
        "//benchmarks/Clustering/K-Center/common:kcenter_quality",
    ],
)
