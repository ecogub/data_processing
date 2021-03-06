ms_pasta_domain_refmap = list(
    hbef = 'knb-lter-hbr',
    hjandrews = 'knb-lter-and',
    konza = 'knb-lter-knz',
    baltimore = 'knb-lter-bes',
    luquillo = 'knb-lter-luq',
    niwot = 'knb-lter-nwt',
    santa_barbara = 'knb-lter-sbc',
    bonanza = 'knb-lter-bnz',
    mcmurdo = 'knb-lter-mcm',
    plum = 'knb-lter-pie',
    arctic = 'knb-lter-arc'
)

get_latest_product_version <- function(prodname_ms, domain, data_tracker){

    vsn_endpoint = 'https://pasta.lternet.edu/package/eml/'

    domain_ref = ms_pasta_domain_refmap[[domain]]
    prodcode = prodcode_from_prodname_ms(prodname_ms=prodname_ms)

    vsn_request = glue(vsn_endpoint, domain_ref, '/', prodcode)

    if(ms_instance$op_system == 'windows'){
        newest_vsn <- xml2::xml_text(xml2::read_html(vsn_request))
    } else{
        newest_vsn <- RCurl::getURLContent(vsn_request, timeout=10)
    }

    newest_vsn = as.numeric(stringr::str_match(newest_vsn,
        '[0-9]+$')[1])

    return(newest_vsn)
}

get_avail_lter_product_sets <- function(prodname_ms, version, domain,
    data_tracker){

    #returns: tibble with url, site_name, component (aka element_name)

    name_endpoint <- 'https://pasta.lternet.edu/package/name/eml/'
    dl_endpoint <- 'https://pasta.lternet.edu/package/data/eml/'

    domain_ref <- ms_pasta_domain_refmap[[domain]]
    prodcode <- prodcode_from_prodname_ms(prodname_ms)

    name_request <- glue(name_endpoint, domain_ref, '/', prodcode, '/',
        version)

    if(ms_instance$op_system == 'windows'){
        reqdata <- xml2::xml_text(xml2::read_html(name_request))
    } else{
        reqdata <- RCurl::getURLContent(name_request)
    }

    reqdata <- strsplit(reqdata, '\n')[[1]]
    reqdata <- grep('Constants', reqdata, invert = TRUE, value = TRUE) #junk filter for hbef. might need flex
    reqdata <- str_match(reqdata, '([0-9a-zA-Z]+),(.+)')

    element_ids = reqdata[,2]
    dl_urls = paste0(dl_endpoint, domain_ref, '/', prodcode, '/', version,
        '/', element_ids)

    names <- str_match(reqdata[,3], '(.+?)_.*')[,2]
    names[names %in% c(domain, network)] = 'sitename_NA'

    names[is.na(names)] <- 'sitename_NA'

    avail_sets <- tibble(url=dl_urls,
        site_name=names,
        component=reqdata[,3])

    return(avail_sets)
}

populate_set_details <- function(tracker, prodname_ms, site_name, avail,
    latest_vsn){
    #tracker=held_data;avail=avail_site_sets

    #must return a tibble with a "needed" column, which indicates which new
    #datasets need to be retrieved

    retrieval_tracker = tracker[[prodname_ms]][[site_name]]$retrieve
    prodcode = prodcode_from_prodname_ms(prodname_ms)

    retrieval_tracker = avail %>%
        mutate(
            avail_version = latest_vsn,
            prodcode_full = NA, #no such thing for lter. could simply omit
            prodcode_id = prodcode,
            prodname_ms = prodname_ms) %>%
        full_join(retrieval_tracker, by='component') %>%
        # filter(status != 'blacklist' | is.na(status)) %>%
        mutate(
            held_version = as.numeric(held_version),
            needed = avail_version - held_version > 0)

    if(any(is.na(retrieval_tracker$needed))){
        msg = paste0('Must run `track_new_site_components` before ',
            'running `populate_set_details`')
        logerror(msg, logger=logger_module)
        stop(msg)
    }

    return(retrieval_tracker)
}

get_lter_data <- function(domain, sets, tracker, silent=TRUE){
    # sets <- new_sets; tracker <- held_data

    if(nrow(sets) == 0) return()

    for(i in 1:nrow(sets)){

        if(! silent) print(paste0('i=', i, '/', nrow(sets)))

        s = sets[i, ]

        msg = glue('Processing {st}, {p}, {c}',
            st=s$site_name, p=s$prodname_ms, c=s$component)
        loginfo(msg, logger=logger_module)

        processing_func = get(paste0('process_0_', s$prodcode_id))
        result = do.call(processing_func,
            args=list(set_details=s, network=network, domain=domain))
        # process_0_1(set_details=s, network=network, domain=domain)

        new_status <- evaluate_result_status(result)
        update_data_tracker_r(network=network, domain=domain,
            tracker_name='held_data', set_details=s, new_status=new_status)
    }
}

download_raw_file <- function(network, domain, set_details, file_type = '.csv') {
    raw_data_dest = glue('{wd}/data/{n}/{d}/raw/{p}/{s}',
                         wd = getwd(),
                         n = network,
                         d = domain,
                         p = set_details$prodname_ms,
                         s = set_details$site_name)

    dir.create(raw_data_dest,
               showWarnings = FALSE,
               recursive = TRUE)

    if(is.null(file_type)) {

        download.file(url = set_details$url,
                      destfile = glue(raw_data_dest,
                                      '/',
                                      set_details$component),
                      cacheOK = FALSE,
                      method = 'curl')
    } else {

        download.file(url = set_details$url,
                      destfile = glue(raw_data_dest,
                                      '/',
                                      set_details$component,
                                      file_type),
                      cacheOK = FALSE,
                      method = 'curl')
    }
}

retrieve_lter <- function(set_details, network, domain) {

    download_raw_file(network = network,
                      domain = domain,
                      set_details = set_details,
                      file_type = NULL)

    return()
}

