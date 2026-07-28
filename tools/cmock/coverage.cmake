# Taken from amazon-freertos repository
cmake_minimum_required(VERSION 3.13)
set(BINARY_DIR ${CMAKE_BINARY_DIR})
file(GLOB_RECURSE cov_files "${BINARY_DIR}/*.gcda")
if(cov_files)
    file(REMOVE ${cov_files})
endif()

# reset coverage counters
execute_process(COMMAND lcov
    --directory ${CMAKE_BINARY_DIR}
    --base-directory ${CMAKE_BINARY_DIR}
    --zerocounters

    COMMAND mkdir -p  ${CMAKE_BINARY_DIR}/coverage
)
# make the initial/baseline capture a zeroed out files
execute_process(COMMAND lcov
    --directory ${CMAKE_BINARY_DIR}
    --base-directory ${CMAKE_BINARY_DIR}
    --initial
    --capture
    # lcov 2.x promotes "cannot open <source>" (e.g. CMakeCCompilerId.c) and an
    # empty trace file from warnings to fatal errors; tolerate both so the
    # baseline capture still produces base_coverage.info.
    --ignore-errors source,empty
    --rc lcov_branch_coverage=1
    --rc genhtml_branch_coverage=1
    --output-file=${CMAKE_BINARY_DIR}/base_coverage.info
)
file(GLOB files "${CMAKE_BINARY_DIR}/bin/tests/*")

set(REPORT_FILE ${CMAKE_BINARY_DIR}/utest_report.txt)
file(WRITE ${REPORT_FILE} "")
# execute all files in bin directory, gathering the output to show it in CI
foreach(testname ${files})
    get_filename_component(test ${testname} NAME_WLE)
    message("Running ${testname}")
    execute_process(COMMAND ${testname} OUTPUT_FILE ${CMAKE_BINARY_DIR}/${test}_out.txt)

    file(READ ${CMAKE_BINARY_DIR}/${test}_out.txt CONTENTS)
    file(APPEND ${REPORT_FILE} "${CONTENTS}")
endforeach()

# generate Junit style xml output
execute_process(COMMAND ruby
    ${CMOCK_DIR}/vendor/unity/auto/parse_output.rb
    -xml ${REPORT_FILE}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# capture data after running the tests
execute_process(COMMAND lcov
    --capture
    --ignore-errors source,empty
    --rc lcov_branch_coverage=1
    --rc genhtml_branch_coverage=1
    --base-directory ${CMAKE_BINARY_DIR}
    --directory ${CMAKE_BINARY_DIR}
    --output-file ${CMAKE_BINARY_DIR}/second_coverage.info
)

# compile baseline results (zeros) with the one after running the tests
execute_process(COMMAND lcov
    --base-directory ${CMAKE_BINARY_DIR}
    --directory ${CMAKE_BINARY_DIR}
    --add-tracefile ${CMAKE_BINARY_DIR}/base_coverage.info
    --add-tracefile ${CMAKE_BINARY_DIR}/second_coverage.info
    --output-file ${CMAKE_BINARY_DIR}/coverage.info
    # --no-external is ignored outside of --capture in lcov 2.x (it warns and
    # is a no-op here); external/system paths are already stripped by the
    # --remove step below. Tolerate an empty tracefile so the merge still runs.
    --ignore-errors empty
    --rc lcov_branch_coverage=1
)

# remove source files from dependencies and unit tests
execute_process(COMMAND lcov
    --rc lcov_branch_coverage=1
    --remove ${CMAKE_BINARY_DIR}/coverage.info *dependency* *unit-test* /usr* */source/ota.c *CMakeCCompilerId* */source/portable/os/ota_os_posix.c
    --output-file ${CMAKE_BINARY_DIR}/coverage.info
    # lcov 2.x promotes an "unused" warning (a --remove pattern that matches no
    # records, e.g. *CMakeCCompilerId* or /usr* when nothing leaked) to a fatal
    # error, which would abort before coverage.info is rewritten. Tolerate it so
    # the remove step always produces the final coverage.info.
    --ignore-errors unused
)

# generate html report
execute_process(COMMAND genhtml
    --rc lcov_branch_coverage=1
    --branch-coverage
    --output-directory ${CMAKE_BINARY_DIR}/coverage
    ${CMAKE_BINARY_DIR}/coverage.info
)

# output coverage summary to console
execute_process(COMMAND lcov
    --rc lcov_branch_coverage=1
    --list ${CMAKE_BINARY_DIR}/coverage.info
)
