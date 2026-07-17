package(default_visibility = ["//visibility:public"])

cc_library(
    name = "ThorupSimple",
    hdrs = [
        "ThorupSimple.h",
        "ThorupSimpleInverse.h",
        "common/ThorupSimpleShared.h",
    ],
    deps = [
        "//gbbs",
        "//benchmarks/BFS/BFSdist:BFSdist",
        "//benchmarks/BFS/BFSdist:BFSdistSeq",
        "//benchmarks/PositiveWeightSSSP/DeltaStepping:DeltaStepping",
        "//benchmarks/PositiveWeightSSSP/DeltaStepping:DeltaSteppingMultiSources",
        "//benchmarks/PositiveWeightSSSP/Dijkstra:Dijkstra",
        "//benchmarks/BFS/BFSdist:BFSdistMultiSources",
        "//benchmarks/BFS/BFSdist:BFSdistSeqMultiSources",
        "//benchmarks/PositiveWeightSSSP/Dijkstra:DijkstraMultiSources",
    ],
)

cc_binary(
    name = "ThorupSimple_main",
    srcs = ["ThorupSimple.cc"],
    deps = [
        ":ThorupSimple",
        "//benchmarks/Clustering/K-Center/common:DispatchMain",
        "//benchmarks/Clustering/K-Center/common:kcenter_quality",
        "//gbbs",
    ],
)
