# encoding: ISO-8859-1
require 'nokogiri'
require 'mechanize'
require 'csv'
require 'scrapers/mcf'


Mechanize.html_parser = Nokogiri::HTML

BASE_URL = "http://corp.sec.state.ma.us"

@br = Mechanize.new { |b|
  b.user_agent_alias = 'Linux Firefox'
  b.max_history=0
  b.retry_change_requests = true
  b.verify_mode = OpenSSL::SSL::VERIFY_NONE
}
PER_PAGE=100

class String
  def pretty
    self.strip
  end
end


class Array
  def strip
    self.collect{|a|a.strip}
  end
end

def scrape(pg,act,rec)
  data = pg.body rescue pg
  records = []
  doc = Nokogiri::HTML(data)
  doc.xpath(".//table[@id='MainContent_SearchControl_grdSearchResultsEntity']/tr[@class='GridRow' or @class='GridAltRow']").each{|tr|
    r = {}
    r["company_name"] = s_text(tr.xpath("./td[1]/a/text()"))
    r["company_number"] = s_text(tr.xpath("./td[2]/text()"))
    r["old_company_number"] = s_text(tr.xpath("./td[3]/text()"))
    r["address"] = a_text(tr.xpath("./td[4]")).join("\n").strip

    records << r.merge(rec)
  }
  tmp = attributes(doc.xpath(".//table[@id='MainContent_SearchControl_grdSearchResultsEntity']/tr[@class='link']/td/table/tr/td[span]/following-sibling::*[1][self::td]/a"),"href").split("'")[3]
  return records,tmp
end

def init()
  @pg = @br.get(BASE_URL + "/CorpWeb/CorpSearch/CorpSearch.aspx")
  @pg.form_with(:id=>"Form1") do |f|
    f['__EVENTTARGET'] = "ctl00$MainContent$rdoByEntityName"
    @pg = f.submit
  end
end

def action()
  list =  (0..9).to_a + ('A'..'Z').sort.to_a
  lstart = get_metadata("list",0)
  list[lstart..-1].each_with_index{|srch,idx|
    params = JSON.parse(get_metadata("form",JSON.generate({'__EVENTTARGET'=>'ctl00$MainContent$ddRecordsPerPage', 'ctl00$MainContent$CorpSearch'=>'rdoByEntityName', 'ctl00$MainContent$txtEntityName'=>srch, 'ctl00$MainContent$ddRecordsPerPage'=>PER_PAGE})))
    begin
      init() if @pg.nil? 
      @pg.form_with(:id=>"Form1") do |f|
        params.each{|k,v| f[k] = v}
        @pg = f.submit
      end
      records,nex = scrape(@pg,"list",{"doc"=>Time.now})
      ScraperWiki.save_sqlite(['company_number'],records,'ocdata')
      break if records.nil? or records.length < PER_PAGE or nex.nil? or nex.empty? 
    
      params = {'__EVENTTARGET'=>'ctl00$MainContent$SearchControl$grdSearchResultsEntity', '__EVENTARGUMENT'=>nex, '__ASYNCPOST'=>'false'}

      
      #tmp_f = {}
      #@pg.form_with(:id=>"Form1").fields.each{|f|
      #  tmp_f[f.name] = f.value
      #}
      #save_metadata("form",JSON.generate(tmp_f))
    end while(true)
    @pg = nil
    delete_metadata("form")
    lstart = lstart + 1
    save_metadata("list",lstart)
  }
  delete_metadata("list")
end

action()
