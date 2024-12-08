#! /bin/bash

ISSUE_ORGS=("srv" "dsh" "aut" "bld" "py")
ISSUE_KINDS=("fix" "new" "con" "ref")
ISSUE_REPOS=("tsk/plan" "tsk/back")
ISSUE_DEFAULT_REPO="tsk/plan"

function issue {
# auxiliary functions
    function check_dependencies {
        dependencies=("tea" "fzf")
        for cmd in "${dependencies[@]}"; do
            if ! command -v "$cmd" &> /dev/null; then
                echo "error: '$cmd' is not installed. Please install it before using this script."
                return 1
            fi
        done
    }

    function show_help {
        echo "Usage: issue [repo] [option] [arguments]

Options:
    help, --help             Show this help message
    n, new                   Create a new issue or interactively enter details
    c, close                 Close an opened issue with specified ID
    o, open                  Open a closed issue with specified ID
    l, ls, list [filter]     List issues, optionally filter by keyword, label, state, or author
                             Filters: k/key/keyword, l/lab/label/labels, s/state, a/author
    repos                    Display available repos
    labels                   Display available kinds/labels
    orgs                     Display available orgs
        "
    }

    function list_options {
        options=("$@")
        IFS='|'; echo "${options[*]}"
    }

    function validate_filter_type {
        filter_type="$1"
        case "$filter_type" in
            k|key|keyword) echo "keyword" ;;
            l|lab|label|labels) echo "labels" ;;
            s|state) echo "state" ;;
            a|author) echo "author" ;;
            *) echo ""; return 1 ;;
        esac
    }

    function collect_issues {
        local repo="$1"
        local state="$2"
        local filter_type="$3"
        local filter_value="$4"
        
        if [[ -z "$filter_type" ]]; then
            tea issues list --output simple --repo "${repo}" --state="${state}" | sed -n '/no gitea login detected/!p'
        else
            tea issues list --output simple --repo "${repo}" --"${filter_type}" "${filter_value}" --state="${state}" | sed -n '/no gitea login detected/!p'
        fi
    }

    function select_issue {
        local issue_list="$1"
        
        local line_count=$(echo "$issue_list" | wc -l)
        local term_height=$(tput lines)
        local display_height=$((line_count * 100 / term_height))
        
        echo -e "$issue_list" | fzf --height="${display_height}%" --layout=reverse --border --ansi --preview-window=right:wrap --color=16
    }

    function manage_issues {
        local action="$1"
        local repo="$2"
        local state="$3"
        local filter_type="$4"
        local filter_value="$5"
        
        local issues
        issues=$(collect_issues "${repo}" "${state}" "${filter_type}" "${filter_value}")

        if [[ -n "${issues}" ]]; then
            local selection
            selection=$(select_issue "${issues}")
            if [[ -n "${selection}" ]]; then
                local issue_id
                issue_id=$(echo "${selection}" | awk '{print $1}')
                if [[ "$action" == "list" ]]; then
                    tea issues --comments --repo "${repo}" "${issue_id}" | sed -n '/no gitea login detected/!p' | sed 's/# //g' | sed -e '/^  #Comments/i---------------------------------'  | sed -e '/^$/d' | sed 's/^/  /' | sed 's/**//g' 
                else
                    tea issues "${action}" --repo "${repo}" "${issue_id}" | sed -n '/no gitea login detected/!p' | sed 's/# //g' | sed -e '/^$/d'
                    if [[ ! "$?" == "0" ]]; then
                        return 1
                    fi
                    echo "Issue ${issue_id} has been ${action}ed."
                fi
            else
                echo "No issue selected."
            fi
        else
            echo "There is no issue to select."
            return 1
        fi
    }

    function new_issue {
        local org_version title description kind_severity kind severity
        local orgs_regex=$(list_options "${ISSUE_ORGS[@]}")
        local kinds_regex=$(list_options "${ISSUE_KINDS[@]}")

        echo "Enter org/version:"
        while true; do
            read -e -r -p "> " org_version
            if [[ -n "$org_version" ]]; then
                if [[ "$org_version" =~ ^(${orgs_regex})/v[0-9]+\.[0-9]+$ ]] ||
                   [[ "$org_version" =~ ^(${orgs_regex})/v[0-9]+$ ]]; then
                    break
                else
                    echo "Please, enter org/version"
                fi
            else
                echo "org/version cannot be empty. Please try again."
            fi
        done

        echo "Enter issue title:"
        while true; do
            read -e -r -p "> " title
            if [[ -n "$title" ]]; then
                break
            else
                echo "Title cannot be empty. Please try again."
            fi
        done

        echo "Enter issue description:"
        while true; do
            read -e -r -p "> " description
            if [[ -n "$description" ]]; then
                break
            else
                echo "Description cannot be empty. Please try again."
            fi
        done

        echo "Enter kind/severity:"
        while true; do
            read -e -r -p "> " kind_severity
            IFS='/' read -r kind severity <<< "$kind_severity"
            if [[ -n "$kind" ]]; then
                break
            else
                echo "At least kind must be provided."
            fi 
        done
    
        tea issues create --repo "${repo}" --title "${org_version}: ${title}" --description "${description}" --labels "kind/$kind,${severity}" | sed -n '/no gitea login detected/!p' | sed 's/# //g' | sed -e '/^$/d'

        echo "ok: The issue has been created."
    }

# issue function properly
    local repo="$ISSUE_DEFAULT_REPO"
    check_dependencies || return 1

    if [[ -z "$1" ]]; then
        tea open --repo "${ISSUE_DEFAULT_REPO}" issues
        return
    fi
    
    if [[ " ${ISSUE_REPOS[*]} " == *" tsk/$1 "* ]]; then
        repo="tsk/$1"
        shift
    fi

    case "$1" in
        help|--help)
            show_help
            return
            ;;
        new|n)
            if [[ -z "$2" ]]; then
                new_issue
                return
            fi

            shift
            local org_version="$1" title="$2" description="$3" kind_severity="$4"

            local orgs_regex=$(list_options "${orgs[@]}")
            if ! [[ "$org_version" =~ ^(${orgs_regex})/v[0-9]+\.[0-9]+$ ]]; then
                echo "error: org/version:'$org_version' is not valid for repo '$repo'."
                return 1
            fi

            if [[ -z "$title" || -z "$description" || -z "$kind_severity" ]]; then
                echo "error: Missing required arguments."
                return 1
            fi
            IFS='/' read -r kind severity <<< "$kind_severity"
            tea issues create --repo "${repo}" --title "${org_version}: ${title}" --description "${description}" --labels "kind/$kind,${severity}" | sed -n '/no gitea login detected/!p' | sed 's/# //g'
            ;;
        close|c)
            shift
            local filter_type=$(validate_filter_type "$1")
            local filter_value="$2"

            if ! [[ -z "$filter_type" || -z "$filter_value" ]]; then
                manage_issues "close" "${repo}" "open" "${filter_type}" "${filter_value}"
            else
                manage_issues "close" "${repo}" "open"
                return 1
            fi

            
            ;;
        open|o)
            shift
            local filter_type=$(validate_filter_type "$1")
            local filter_value="$2"
            if ! [[ -z "$filter_type" || -z "$filter_value" ]]; then
                manage_issues "open" "${repo}" "closed" "${filter_type}" "${filter_value}"
            else
                manage_issues "open" "${repo}" "closed"
                return 1
            fi
            ;;
        list|ls)
            shift
            local filter_type=$(validate_filter_type "$1")
            local filter_value="$2"

            if ! [[ -z "$filter_type" || -z "$filter_value" ]]; then
                manage_issues "list" "${repo}" "" "${filter_type}" "${filter_value}"
            else
                manage_issues "list" "${repo}"                
            fi            
            ;;
        repos)
            echo "Repos: ${ISSUE_REPOS[*]}"
            ;;
        labels)
            echo "Labels: ${ISSUE_KINDS[*]}"
            ;;
        orgs)
            echo "Orgs: ${ISSUE_ORGS[*]}"
            ;;
        *)
            echo "error: Option '$1' not defined. Use 'help' option for usage."
            return 1
            ;;
    esac
}

