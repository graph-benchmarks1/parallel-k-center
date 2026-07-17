licenses(["notice"])

package(
    default_visibility = ["//visibility:public"],
)

cc_library(
    name = "Forster",
    hdrs = ["Forster.h"],
    deps = [
        "//gbbs",
        "//benchmarks/PositiveWeightSSSP/RR:RR",
    ],
)

cc_binary(
    name = "Forster_main",
    srcs = ["Forster.cc"],
    deps = [
        ":Forster",
        "//benchmarks/Clustering/K-Center/common:DispatchMain",
        "//benchmarks/Clustering/K-Center/common:kcenter_quality",
    ],
)
