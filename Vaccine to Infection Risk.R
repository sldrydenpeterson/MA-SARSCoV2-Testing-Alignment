library(tidyverse)



# load data from MDPH
load(file = "vaccine.sex.Rdata")
load(file = "vaccine.age.Rdata")
load(file = "vaccine.town.Rdata")
load(file = "vaccine.race.Rdata") #just to get the race/eth breakdown by town

#weekly MDPH printed summary reports, statewide
load(file = "VaxRace.Rdata")
load(file = "CasesRace.Rdata")


#Last data available at time of analysis
analysisdt<-as.Date("2021-04-08")

#get town prevalence of vaccine, using separate file from MDPH
town.vax1 <- (left_join( vaccine.town %>% filter(reportdate == analysisdt) %>%
                           group_by(Town)%>%
                           filter(Age_group !="Total")%>%
                           summarise(fullvax.total=sum(fullvax, na.rm = TRUE),
                                     population=sum(pop, na.rm = TRUE))%>%
                           mutate(vaccine_prev=fullvax.total*100/population,
                                  Town=str_replace(Town, " \\s*\\([^\\)]+\\)", "")  ), #remove parenthetic phrase
                         
                         town.age <- vaccine.town %>% filter(reportdate == max(as.Date(reportdate))) %>%
                           group_by(Town)%>%
                           mutate(Town=str_replace(Town, " \\s*\\([^\\)]+\\)", "")  ) %>% #remove parenthetic phrase
                           filter(Age_group=="65-74 Years" | Age_group=="75+ Years" ) %>%
                           summarise(age65up=sum(pop)),
                         by="Town") %>%
                mutate(age65up.pct=age65up/population)) %>% dplyr::select(-age65up)


#get boston neighborhood prevalence of vaccine
boston<- c("West Roxbury", "Roslindale", "Hyde Park", "Mattapan", "Jamaica Plain", "Dorchester Codman", "Dorchester Uphams", "Roxbury",
           "Fenway", "Allston Brighton", "Back Bay Downtown", "South End", "South Boston", "Charlestown", "East Boston")

#read in .csv files of zipcodes and population
MAtownsbos <- read_csv("MAtowns.csv") %>% filter(Town %in% boston)


bos.vax1<-left_join(MAtownsbos, vaccine.sex %>%  ungroup()%>%
                      filter(reportdate == analysisdt), by="zipcode") %>%
  group_by(Town) %>%
  summarise(population=mean(town_population, na.rm= TRUE),
            fullvax.total=sum(fullvax.total, na.rm= TRUE)) %>%
  mutate(vaccine_prev=fullvax.total*100/population,
         age65up.pct = 0.1166) # boston wide population, does not use zipcode-specific

#add boston neighbhoorhoods to MA town table
town.vax2<- rbind(town.vax1, bos.vax1) %>%
  filter (Town !="Boston", Town !="Unspecified")

#read in incidence covid cases and characteristics of communities
allcovidtowns <-left_join(read_csv("allcovidtowns.csv", guess_max=10000),
                          MAtownSES <-read_csv("MAtownSES.csv", guess_max=10000), by="Town") %>%
  rename(SVI_SES=RPL_THEME1.town, SVI_ages_disability=RPL_THEME2.town,
         SVI_minority=RPL_THEME3.town, SVI_house=RPL_THEME4.town,
         SVI_overall=RPL_THEMES.town)  %>%
  # Socioeconomic – RPL_THEME1
  # Household Composition & Disability – RPL_THEME2
  # Minority Status & Language – RPL_THEME3
  # Housing Type & Transportation – RPL_THEME4
  # Overall tract rankings:  RPL_THEMES.
  mutate(
    quartile.SVI_SES=cut(SVI_SES, breaks=c(0, 0.25, 0.50, 0.75, 1), labels=FALSE),
    quartile.SVI_ages_disability=cut(SVI_ages_disability, breaks=c(0, 0.25, 0.50, 0.75, 1), labels=FALSE),
    quartile.SVI_minority=cut(SVI_minority, breaks=c(0, 0.25, 0.50, 0.75, 1), labels=FALSE),
    quartile.SVI_house=cut(SVI_house, breaks=c(0, 0.25, 0.50, 0.75, 1), labels=FALSE),
    quartile.SVI_overall=cut(SVI_overall, breaks=c(0, 0.25, 0.50, 0.75, 1), labels=FALSE)
  ) 



town.vax<-left_join(town.vax2, allcovidtowns %>% filter(date == analysisdt), by="Town") %>%
  mutate(cumulative_incidence=Count*100/population,
         VnR=vaccine_prev/cumulative_incidence, 
         blacklatinx.pct=(pop.black + pop.latino)/pop.total, 
         blacklatinx.ord=cut(blacklatinx.pct, breaks=c(-1, 0.20, Inf), labels=c(1,2)),
         population.ord=as.numeric(cut(population, breaks=c(-1, 50000, Inf), labels=c(1,2))),
         population.10=population/10000,
         age65up.ord=as.numeric(cut(age65up.pct, breaks=c(-1, 0.15, 0.2, 0.25, Inf), labels=c(1,2,3,4)))) 

totalpop <- town.vax %>%
  tally(population)

totalcovid<- town.vax %>%
  tally(Count)

totalvax<- town.vax %>%
  tally(fullvax.total)

totalvax/totalcovid

min(town.vax$vaccine_prev)
max(town.vax$vaccine_prev)

totalcovid/totalpop
totalvax/totalpop



## Poisson model
library(sandwich)
library(pscl)


summary(m1 <- glm(VnR ~ blacklatinx.ord + population.ord + quartile.SVI_SES + age65up.ord,
                  family="poisson", data=town.vax %>% filter(population>3000)))

cov.m1 <- vcovHC(m1, type="HC0")
std.err <- sqrt(diag(cov.m1))
r.est <- cbind(Estimate= exp(coef(m1)), "Robust SE" = std.err,
               "Pr(>|z|)" = 2 * pnorm(abs(coef(m1)/std.err), lower.tail=FALSE),
               LL = exp(coef(m1) - 1.96 * std.err),
               UL = exp(coef(m1) + 1.96 * std.err))
r.est

#check deviance
with(m1, cbind(res.deviance = deviance, df = df.residual,
               p = pchisq(deviance, df.residual, lower.tail=FALSE)))

detach(package:pscl,unload=TRUE)
detach(package:sandwich,unload=TRUE)

library(REAT)

CasesRace1<-CasesRace %>%
  filter(date == analysisdt) %>%
  mutate(AllOther=AI.AN + Multi + NH.PI + Unknown) %>%
  dplyr::select(date, Asian, Black, Hispanic, White, AllOther) %>%
  pivot_longer(cols=c(Asian:AllOther), names_to = "RaceEth", values_to = "CaseCount")

VaxRace1<- VaxRace %>% filter(date == analysisdt) %>%
  mutate(AllOther=AI.AN + Multi + NH.PI + Unknown) %>%
  dplyr::select(date, Asian, Black, Hispanic, White, AllOther) %>%
  pivot_longer(cols=c(Asian:AllOther), names_to = "RaceEth", values_to = "VaccineCount") 

## developing Lorenz curves

##by individuals
#vaccines and cases by race/ethnic categories and combined for all categories
total.byinvid<-left_join(CasesRace1, VaxRace1, by=c("date", "RaceEth")) 
totalvaxMA.byinvid<-(total.byinvid %>% tally(VaccineCount))$n
totalcaseMA.byinvid<-(total.byinvid %>% tally(CaseCount))$n


#cumulative number of cases/vaccines for Lorenz
g1<-total.byinvid %>%  
  mutate(VnR=VaccineCount/CaseCount) %>%
  arrange(VnR) %>%
  mutate(cum_Count=cumsum(CaseCount),
         cum_Count_prop=cum_Count/totalcaseMA.byinvid,
         cum_fullvax=cumsum(VaccineCount), 
         cum_fullvax_prop=cum_fullvax/totalvaxMA.byinvid,
         identity_x=cum_Count_prop,
         identity_y=cum_Count_prop) %>%
  dplyr::select(cum_fullvax_prop, cum_Count_prop, identity_x, identity_y, RaceEth, VnR)

#calculating Hoover and Gini indices using REAT package
g1.hoover<-hoover(total.byinvid$VaccineCount, total.byinvid$CaseCount)
g1.gini<-gini(total.byinvid$VaccineCount, total.byinvid$CaseCount, coefnorm = FALSE,  na.rm = TRUE)

#need to duplicate to get colors to go from min to max
g2<-rbind(g1, g1) %>%
  arrange(VnR) %>%
  mutate(cum_fullvax_prop=lag(cum_fullvax_prop,1),
         cum_Count_prop=lag(cum_Count_prop,1),
         RaceEth=fct_reorder(fct_recode(as.factor(RaceEth), 
                                        "Latinx" = "Hispanic",
                                        "Multiple/Other" = "AllOther" ), VnR),
         identity_x = if_else(is.na(cum_Count_prop),0,cum_Count_prop),
         identity_y = if_else(is.na(cum_Count_prop),0,cum_Count_prop))%>%
  replace(is.na(.), 0)


jama5<-c(  "#374E55ff", "#80796BFF","#DF8F44FF", "#B24745FF", "#00A1D5FF")
l2<-g2 %>%
  ggplot() +
  geom_ribbon(aes(ymin=cum_fullvax_prop-0.015, ymax=cum_fullvax_prop+0.015, x=cum_Count_prop, fill=RaceEth))+
  geom_line(aes(x=identity_x, y=identity_y),linetype="dashed") +
  theme_light() +
  labs(title= "Distribution of Vaccination and SARS-CoV-2 Infection\namong Massachusetts Residents",
       x="Cumulative Proportion of Confirmed SARS-CoV-2 Infection",
       y="Cumulative Proportion of Fully-Vaccinated Individuals") +
  scale_fill_manual(values=jama5, name="Race/Ethnicity")+
  annotate("text", x=0.8, y=0.1, label=paste0("Gini Index ", round(g1.gini,2), "\nHoover Index ", round(g1.hoover,2)), size=7)+
  theme(legend.position = c(.3, .8), aspect.ratio = 1, panel.grid.minor = element_blank(),
        panel.grid.major = element_blank(), plot.title = element_text(size = rel(1.5)),
        axis.title = element_text(size = rel(1.5)), axis.text = element_text(size = rel(1.5) ),
        legend.text = element_text(size = rel(1.5)), legend.title = element_text(size = rel(1.5)) )


totalvaxMA<-(town.vax %>% tally(fullvax.total))$n
totalcaseMA<-(town.vax %>% tally(Count))$n
jama<-c(  "#374E55ff", "#80796BFF","#DF8F44FF", "#B24745FF")

##by Towns
g3<-town.vax %>% filter(population>3000) %>%
  arrange(desc(blacklatinx.pct)) %>%  #arrange by SES
  mutate(cum_Count=cumsum(Count), 
         cum_Count_prop=cum_Count/totalcaseMA,
         cum_fullvax=cumsum(fullvax.total),
         cum_fullvax_prop=cum_fullvax/totalvaxMA,
         identity_x=cum_Count_prop,
         identity_y=cum_Count_prop) %>%
  mutate(blacklatinx.cat=cut(blacklatinx.pct, breaks=c(-1, 0.05, 0.1, 0.2, Inf),
                             labels=c("0 to 5%", "5 to 10%", "10 to 20%", "> 20%"))) %>%
  dplyr::select(Town, Count, cum_Count, cum_Count_prop, fullvax.total, cum_fullvax, cum_fullvax_prop, blacklatinx.cat,
                identity_y, identity_x, blacklatinx.pct)

g3.hoover<-hoover(town.vax$fullvax.total, town.vax$Count)
g3.gini<-gini(town.vax$fullvax.total, town.vax$Count, coefnorm = FALSE, na.rm = TRUE)

detach(package:REAT, unload=TRUE)

# need to duplicate to allow colors to go from min to max cum cases/vax
g4<-rbind(g3, g3) %>%
  arrange(desc(blacklatinx.pct)) %>%
  mutate(cum_fullvax_prop=lag(cum_fullvax_prop,1),
         cum_Count_prop=lag(cum_Count_prop,1),
         identity_x = if_else(is.na(cum_Count_prop),0,cum_Count_prop),
         identity_y = if_else(is.na(cum_Count_prop),0,cum_Count_prop))%>%
  replace(is.na(.), 0) %>%
  mutate(blacklatinx.cat= fct_reorder(blacklatinx.cat, desc(blacklatinx.pct)))

l1<- g4 %>%
  ggplot() +
  geom_ribbon(aes(ymin=cum_fullvax_prop-0.015, ymax=cum_fullvax_prop+0.015,x=cum_Count_prop, fill=blacklatinx.cat))+
  geom_line(aes(x=identity_x, y=identity_y),linetype="dashed") +
  theme_light() +
  labs(title= "Distribution of Vaccination and SARS-CoV-2 Infection\namong Massachusetts Communities",
       x="Cumulative Proportion of Confirmed SARS-CoV-2 Infection",
       y="Cumulative Proportion of Fully-Vaccinated Individuals") +
  scale_fill_manual(values=jama, name="Community\nBlack and/or Latinx\nProportion")+
  annotate("text", x=0.8, y=0.1, label=paste0("Gini Index ", round(g3.gini,2), "\nHoover Index ", round(g3.hoover,2)),size=7)+
  theme(legend.position = c(.3, .8), aspect.ratio = 1, panel.grid.minor = element_blank(),
        panel.grid.major = element_blank(), plot.title = element_text(size = rel(1.5)),
        axis.title = element_text(size = rel(1.5)), axis.text = element_text(size = rel(1.5) ),
        legend.text = element_text(size = rel(1.5)), legend.title = element_text(size = rel(1.5)) )
library(patchwork)
l1 +l2 + plot_layout(ncol=2) + plot_annotation(tag_levels = 'A')
ggsave("~/Dropbox (Partners HealthCare)/GitHub/Ma-Covid-Testing/Lorenz plot race.pdf", units = "in", width = 16, height=8)




#mean VIR for MA
MAmeanVIR <- ((town.vax %>% tally(fullvax.total)) / (town.vax %>% tally(Count)))$n


jama<-c(  "#374E55ff", "#80796BFF","#DF8F44FF", "#B24745FF")
ggplot(town.vax %>% filter(population >25000), aes(x=reorder(Town, SVI_SES), 
                                                   y=VnR, fill=as.factor(quartile.SVI_SES)))+
  geom_col()+ theme_classic() + 
  scale_fill_manual(values=jama, name="Socioeconomic Vulnerabilty\n(CDC SVI Percentile)",
                    labels=c("Low", "Low to Moderate","Moderate to High",  "High"))  +
  theme(legend.position = c(.95, .95), legend.justification = c(1, 1), 
        legend.direction = "vertical",axis.text.x=element_text(angle=90, hjust=1, vjust=0.5)) +
  geom_hline(yintercept = MAmeanVIR, linetype="dashed") +
  annotate("text", x=93, y=MAmeanVIR+0.2, label=paste0("Massachusetts mean: ", round(MAmeanVIR, 2)), hjust=1)+
  labs(x="Communities (ordered by vulnerabilty)", y="Vaccination to Infection Risk Ratio")
ggsave("Town VIR ratio by SVI.pdf", units = "in", width = 10, height=8)
