clear; 
close all; 
clc;

% Input da esercizio 5 (sigma storica EUROSTOXX50) 
% Richiamo wrapper (da creare a parte) che esegue esercizio_V.m e restituisce sigma
sigma_annua_rendimenti_storici_EUROSTOXX50 = estrai_sigma_da_esercizio_V();
% Input da esercizio 7 (curva EUR OIS bootstrappata)
% Richiamo wrapper (da creare a parte) che esegue esercizio_VII.m e restituisce tabella e r_1M
[Tabella_Zero_Rate, tasso_riskfree_1M] = estrai_curvaOIS_da_esercizio_VII();
% Tengo solo ciò che mi serve per il punto VIII
clearvars -except sigma_annua_rendimenti_storici_EUROSTOXX50 Tabella_Zero_Rate tasso_riskfree_1M;

t0 = datetime(2025, 12, 11);                                                % data in cui abbiamo scaricato i dati
St0 = 5735.21;                                                              % preso da screen GP_Historical_EUROSTOXX50
q = 2.78/100;
Nozionale = 100;
maturity = 4;
tempo_pagamento_cedole = 0.5;
tasso_cedolare = 0.04;
% Parametri per la simulazione del moto geometrico browniano
Numero_simulazioni = 20000;                                                 
T = 5;                                                                      % orizzonte temporale in anni
dt = 1/252;                                                                 % passo temporale giornaliero (252 giorni di trading all'anno)

% Lettura tabella CDS da Excel
CDSV_Credit_Agricole = readtable("CDSV_Credit_Agricole.xlsx", "Sheet", "Foglio1", "VariableNamingRule","preserve");
PROBABILITA_DEFAULT_Credit_Agricole = CDSV_Credit_Agricole(:, ["Maturity", "Default Probability"]);
recovery_rate = 0.40;                                                       % preso da screen CDSV Credit Agricole
% Controllo colonna Spread (necessaria per bootstrap)
if ~ismember("Spread", string(CDSV_Credit_Agricole.Properties.VariableNames))
    error("Per il bootstrap manca la colonna 'Spread' in CDSV_Credit_Agricole.xlsx. Verifica il nome colonna.");
end
Tabella_Default_Bootstrap_CA = bootstrap_probabilita_default_da_CDS(CDSV_Credit_Agricole, Tabella_Zero_Rate, t0, maturity, recovery_rate);

% Fix curva CDS: converto Maturity in anni numerici e sistemo PD/Survival
% Converto maturity CDS in anni (double) rispetto a t0
if isdatetime(PROBABILITA_DEFAULT_Credit_Agricole.Maturity)
    maturity_CDS_anni = days(PROBABILITA_DEFAULT_Credit_Agricole.Maturity - t0) / 360;
elseif isnumeric(PROBABILITA_DEFAULT_Credit_Agricole.Maturity)
    maturity_CDS_anni = PROBABILITA_DEFAULT_Credit_Agricole.Maturity(:);
    if any(isfinite(maturity_CDS_anni)) && median(maturity_CDS_anni(isfinite(maturity_CDS_anni))) > 10000
        maturity_CDS_datetime = datetime(maturity_CDS_anni, "ConvertFrom", "excel");
        maturity_CDS_anni = days(maturity_CDS_datetime - t0) / 360;
    end
elseif iscell(PROBABILITA_DEFAULT_Credit_Agricole.Maturity) || isstring(PROBABILITA_DEFAULT_Credit_Agricole.Maturity)
    try
        maturity_CDS_datetime = datetime(PROBABILITA_DEFAULT_Credit_Agricole.Maturity);
        maturity_CDS_anni = days(maturity_CDS_datetime - t0) / 360;
    catch
        error("Formato Maturity nel file CDS non convertibile in datetime. Controlla Excel.");
    end
else
    error("Tipo Maturity nel file CDS non gestito.");
end
PD = PROBABILITA_DEFAULT_Credit_Agricole.("Default Probability")(:);
% Se PD è in percentuale, converto in decimale
if median(PD(isfinite(PD))) > 1
    PD = PD/100;
    warning("Ho convertito Default Probability da percentuale a decimale.");
end
% Pulizia
indici_validi = isfinite(maturity_CDS_anni) & maturity_CDS_anni > 0 & isfinite(PD);
maturity_CDS_anni = maturity_CDS_anni(indici_validi);
PD = PD(indici_validi);
% Ordino e gestisco duplicati maturity (media)
[maturity_ordinata, indice_sort] = sort(maturity_CDS_anni);
PD_ordinata = PD(indice_sort);
[maturity_unica, ~, gruppi] = unique(maturity_ordinata);
PD_unica = accumarray(gruppi, PD_ordinata, [], @mean);
if any(diff(PD_unica) < -1e-10)
    warning("Default Probability non monotona crescente: potrebbe non essere cumulata. Verifica la definizione della colonna.");
end
% Ricostruisco le tabelle tenendo maturity originale (data) che quella numerica (anni)
maturity_originale_filtrata = CDSV_Credit_Agricole.("Maturity");
maturity_originale_filtrata = maturity_originale_filtrata(indici_validi);   % stessi validi usati su maturity_CDS_anni/PD
maturity_originale_ordinata = maturity_originale_filtrata(indice_sort);     % stesso sort di maturity_ordinata
maturity_originale_unica = accumarray(gruppi, (1:numel(gruppi))', [], @(v) v(1));
maturity_originale_unica = maturity_originale_ordinata(maturity_originale_unica);
PROBABILITA_DEFAULT_Credit_Agricole = table(maturity_originale_unica, maturity_unica, PD_unica, 'VariableNames', {'Maturity_Originale','Maturity_Anni','Default_Probability'});
PROBABILITA_SURVIVAL_Credit_Agricole = table();
PROBABILITA_SURVIVAL_Credit_Agricole.Maturity_Originale = maturity_originale_unica;
PROBABILITA_SURVIVAL_Credit_Agricole.Maturity_Anni = maturity_unica;
PROBABILITA_SURVIVAL_Credit_Agricole.Survival_Probability = 1 - PD_unica;
% Controllo che le probabilità (survival) siano in [0,1] - da file
if any(PROBABILITA_SURVIVAL_Credit_Agricole.Survival_Probability < 0 | PROBABILITA_SURVIVAL_Credit_Agricole.Survival_Probability > 1)
    warning("Attenzione: Survival Probability fuori da [0,1]. Verifica Default Probability nel file (forse è in %).");
end
% Setup griglia temporale simulazione
numero_step = round(T/dt) + 1;                                              % include t=0
rng(1);                                                                     % riproducibilità

% Simulazione Geometric Brownian Motion sotto Q: drift = (r - q)
drift_giornaliero = (tasso_riskfree_1M - q - 0.5 * sigma_annua_rendimenti_storici_EUROSTOXX50^2) * dt;
diffusione_giornaliera = sigma_annua_rendimenti_storici_EUROSTOXX50 * sqrt(dt);
matrice_indice_simulato = zeros(Numero_simulazioni, numero_step);
matrice_indice_simulato(:,1) = St0;
Z = randn(Numero_simulazioni, numero_step-1);
for t = 2:numero_step
    matrice_indice_simulato(:,t) = matrice_indice_simulato(:,t-1) .* exp(drift_giornaliero + diffusione_giornaliera .* Z(:,t-1));
end

% Date cedola del bond (anni)
tempi_date_cedola = (tempo_pagamento_cedole:tempo_pagamento_cedole:maturity)';   
numero_date_cedola = numel(tempi_date_cedola);
% Indici sulla griglia giornaliera
indici_date_cedola = round(tempi_date_cedola/dt) + 1;                       % indici interi per subscript
indici_date_cedola(indici_date_cedola < 1) = 1;
indici_date_cedola(indici_date_cedola > numero_step) = numero_step;
% Valori simulati dell'indice alle date cedola (tutte le traiettorie)
indice_alle_date_cedola = matrice_indice_simulato(:, indici_date_cedola);   % Numero_simulazioni x numero_date_cedola
% Discount factors OIS alle date cedola
discount_factor_nodi = exp(-Tabella_Zero_Rate.ZeroRate .* Tabella_Zero_Rate.Maturity);
discount_factor_date_cedola = exp(interp1(Tabella_Zero_Rate.Maturity, log(discount_factor_nodi), tempi_date_cedola, 'linear', 'extrap'));

% Survival alle date cedola:
%   A) senza bootstrap: da Default Probability nel file
%   B) bootstrap: da CDS spread (Tabella_Default_Bootstrap_CA)
% A) Survival da file (no bootstrap)
survival_date_cedola_file = interp1(PROBABILITA_SURVIVAL_Credit_Agricole.Maturity_Anni, PROBABILITA_SURVIVAL_Credit_Agricole.Survival_Probability, tempi_date_cedola, 'linear', 'extrap');
survival_date_cedola_file = max(min(survival_date_cedola_file,1),0);
% B) Survival bootstrap
survival_date_cedola_bootstrap = interp1(Tabella_Default_Bootstrap_CA.Maturity_Anni, Tabella_Default_Bootstrap_CA.Survival_Probability, tempi_date_cedola, 'linear');
survival_date_cedola_bootstrap = max(min(survival_date_cedola_bootstrap,1),0);

% Recovery leg (mid-point su griglia cedole semestrali)
tempi_cedola_precedenti = [0; tempi_date_cedola(1:end-1)];
tempi_cedola_mezzo = (tempi_cedola_precedenti + tempi_date_cedola)/2;
% Discount_Factor ai midpoint (per default leg)
discount_factor_cedola_mezzo = exp(interp1(Tabella_Zero_Rate.Maturity, log(discount_factor_nodi), tempi_cedola_mezzo, 'linear', 'extrap'));
% Delta PD per intervallo: probabilita_survival_0_t(t_{i-1}) - probabilita_survival_0_t(t_i)
survival_file_precedente = [1; survival_date_cedola_file(1:end-1)];
delta_PD_file = max(survival_file_precedente - survival_date_cedola_file, 0);
survival_bootstrap_precedente = [1; survival_date_cedola_bootstrap(1:end-1)];
delta_PD_bootstrap = max(survival_bootstrap_precedente - survival_date_cedola_bootstrap, 0);
% Cumulata PV recovery fino a ciascuna data (utile per stop a call)
PV_recovery_cumulata_file = Nozionale * recovery_rate * cumsum(discount_factor_cedola_mezzo .* delta_PD_file);
PV_recovery_cumulata_bootstrap = Nozionale * recovery_rate * cumsum(discount_factor_cedola_mezzo .* delta_PD_bootstrap);

% PREZZO 1: uso Sti = media delle traiettorie
Sti= mean(indice_alle_date_cedola, 1)';                                     % numero_date_cedola x 1
indicatore_coupon_media = (Sti./ St0 > 0.95);
indicatore_call_media = (Sti./ St0 > 1.15);
flussi_cassa_media = zeros(numero_date_cedola, 1);
indice_prima_call_media = find(indicatore_call_media, 1, 'first');
if isempty(indice_prima_call_media)
    flussi_cassa_media = Nozionale * tasso_cedolare .* indicatore_coupon_media;
    flussi_cassa_media(end) = flussi_cassa_media(end) + Nozionale;
else
    flussi_cassa_media(1:indice_prima_call_media) = Nozionale * tasso_cedolare .* indicatore_coupon_media(1:indice_prima_call_media);
    flussi_cassa_media(indice_prima_call_media) = flussi_cassa_media(indice_prima_call_media) + Nozionale;
end
% Indice ultima data rilevante (stop a call se presente)
if isempty(indice_prima_call_media)
    indice_stop_media = numero_date_cedola;
else
    indice_stop_media = indice_prima_call_media;
end
PV_recovery_media_file = PV_recovery_cumulata_file(indice_stop_media);
PV_recovery_media_bootstrap = PV_recovery_cumulata_bootstrap(indice_stop_media);
% Prezzo con survival da file (A)
prezzo_bond_media_file = sum(flussi_cassa_media(1:indice_stop_media) .* discount_factor_date_cedola(1:indice_stop_media) .* survival_date_cedola_file(1:indice_stop_media)) + PV_recovery_media_file;
% Prezzo con survival bootstrap (B)
prezzo_bond_media_bootstrap = sum(flussi_cassa_media(1:indice_stop_media) .* discount_factor_date_cedola(1:indice_stop_media) .* survival_date_cedola_bootstrap(1:indice_stop_media)) + PV_recovery_media_bootstrap;
fprintf("\nPrezzo bond (Sti=MEDIA traiettorie) - NO BOOTSTRAP (da file) = %.6f\n", prezzo_bond_media_file);
fprintf("Prezzo bond (Sti=MEDIA traiettorie) - BOOTSTRAP (da CDS spread) = %.6f\n", prezzo_bond_media_bootstrap);

% PREZZO 2: indicatrice per singola traiettoria (pathwise)
indicatore_coupon_path = (indice_alle_date_cedola ./ St0 > 0.95);           % numero simulazioni x numero date
indicatore_call_path = (indice_alle_date_cedola ./ St0 > 1.15);
flussi_cassa_path = Nozionale * tasso_cedolare .* indicatore_coupon_path;   % coupon condizionali
% Gestione callability per traiettoria (prima data in cui call=1)
for probabilita_survival_0_t = 1:Numero_simulazioni
    indice_call_redemption = find(indicatore_call_path(probabilita_survival_0_t,:), 1, 'first');
    if isempty(indice_call_redemption)
        flussi_cassa_path(probabilita_survival_0_t, end) = flussi_cassa_path(probabilita_survival_0_t, end) + Nozionale;    % rimborso a maturity
    else
        flussi_cassa_path(probabilita_survival_0_t, indice_call_redemption) = flussi_cassa_path(probabilita_survival_0_t, indice_call_redemption) + Nozionale;  % rimborso a call
        if indice_call_redemption < numero_date_cedola
            flussi_cassa_path(probabilita_survival_0_t, indice_call_redemption+1:end) = 0;         % annullo flussi successivi
        end
    end
end
% Indice stop per traiettoria (call se presente, altrimenti maturity)
indice_stop_traiettoria = numero_date_cedola * ones(Numero_simulazioni, 1);
for probabilita_survival_0_t = 1:Numero_simulazioni
    indice_call_redemption = find(indicatore_call_path(probabilita_survival_0_t,:), 1, 'first');
    if ~isempty(indice_call_redemption)
        indice_stop_traiettoria(probabilita_survival_0_t) = indice_call_redemption;
    end
end
% Prezzo per traiettoria e media Monte Carlo
% Survival da file
fattore_sconto_survival_file = (discount_factor_date_cedola .* survival_date_cedola_file)';     % 1 x numero date
valore_attuale_traiettoria_file = sum(flussi_cassa_path .* fattore_sconto_survival_file, 2) + PV_recovery_cumulata_file(indice_stop_traiettoria);
prezzo_bond_pathwise_file = mean(valore_attuale_traiettoria_file);
deviazione_standard_file = std(valore_attuale_traiettoria_file);
errore_standard_file = deviazione_standard_file / sqrt(Numero_simulazioni);
IC95_file = [prezzo_bond_pathwise_file - 1.96*errore_standard_file, prezzo_bond_pathwise_file + 1.96*errore_standard_file];
fprintf("\nPrezzo bond PATHWISE - NO bootstrap (da file) = %.6f\n", prezzo_bond_pathwise_file);
fprintf("IC 95%% Monte Carlo (pathwise) - NO bootstrap = [%.6f, %.6f]\n", IC95_file(1), IC95_file(2));
% Survival bootstrap
fattore_sconto_survival_bootstrap = (discount_factor_date_cedola .* survival_date_cedola_bootstrap)';     % 1 x numero date
valore_attuale_traiettoria_bootstrap = sum(flussi_cassa_path .* fattore_sconto_survival_bootstrap, 2) + PV_recovery_cumulata_bootstrap(indice_stop_traiettoria);
prezzo_bond_pathwise_bootstrap = mean(valore_attuale_traiettoria_bootstrap);
deviazione_standard_bootstrap = std(valore_attuale_traiettoria_bootstrap);
errore_standard_bootstrap = deviazione_standard_bootstrap / sqrt(Numero_simulazioni);
IC95_bootstrap = [prezzo_bond_pathwise_bootstrap - 1.96*errore_standard_bootstrap, prezzo_bond_pathwise_bootstrap + 1.96*errore_standard_bootstrap];
fprintf("Prezzo bond PATHWISE - BOOTSTRAP (da CDS spread) = %.6f\n", prezzo_bond_pathwise_bootstrap);
fprintf("IC 95%% Monte Carlo (pathwise) - BOOTSTRAP = [%.6f, %.6f]\n", IC95_bootstrap(1), IC95_bootstrap(2));

%  Grafici confronto prezzi + IC 95% (A: NO BOOTSTRAP, B: BOOTSTRAP)
etichette_metodi = {'Sti = media traiettorie','Pathwise (MC)'};
% Grafico da file
valori_prezzo_A = [prezzo_bond_media_file; prezzo_bond_pathwise_file];
figure;
grid on; 
hold on;
bar(1:2, valori_prezzo_A, 'FaceAlpha', 0.6);
% Marker sopra le barre (coerenti con A)
plot(1, prezzo_bond_media_file, 'o', 'MarkerSize', 7, 'LineWidth', 1.5);
plot(2, prezzo_bond_pathwise_file, 'o', 'MarkerSize', 7, 'LineWidth', 1.5);
% Barra di errore (IC 95%) sul pathwise (A)
errore_superiore_A = IC95_file(2) - prezzo_bond_pathwise_file;
errore_inferiore_A = prezzo_bond_pathwise_file - IC95_file(1);
errorbar(2, prezzo_bond_pathwise_file, errore_inferiore_A, errore_superiore_A, 'LineStyle', 'none', 'LineWidth', 1.8, 'CapSize', 12);
% Etichette numeriche sopra le barre
for i = 1:2
    text(i, valori_prezzo_A(i), sprintf('%.4f', valori_prezzo_A(i)), 'HorizontalAlignment','center', 'VerticalAlignment','bottom');
end
xticks(1:2);
xticklabels(etichette_metodi);
ylabel('Prezzo');
title('Bond Credit Agricole: confronto metodi (NO bootstrap - da file)');
minY_A = min([valori_prezzo_A; IC95_file(:)]);
maxY_A = max([valori_prezzo_A; IC95_file(:)]);
margine_A = 0.08 * (maxY_A - minY_A + eps);
ylim([minY_A - margine_A, maxY_A + 2*margine_A]);
box on; 
hold off;
% Grafico bootstrap
valori_prezzo_B = [prezzo_bond_media_bootstrap; prezzo_bond_pathwise_bootstrap];
figure;
grid on; 
hold on;
bar(1:2, valori_prezzo_B, 'FaceAlpha', 0.6);
% Marker sopra le barre (coerenti con B)
plot(1, prezzo_bond_media_bootstrap, 'o', 'MarkerSize', 7, 'LineWidth', 1.5);
plot(2, prezzo_bond_pathwise_bootstrap, 'o', 'MarkerSize', 7, 'LineWidth', 1.5);
% Barra di errore (IC 95%) sul pathwise (B)
errore_superiore_B = IC95_bootstrap(2) - prezzo_bond_pathwise_bootstrap;
errore_inferiore_B = prezzo_bond_pathwise_bootstrap - IC95_bootstrap(1);
errorbar(2, prezzo_bond_pathwise_bootstrap, errore_inferiore_B, errore_superiore_B, 'LineStyle', 'none', 'LineWidth', 1.8, 'CapSize', 12);
% Etichette numeriche sopra le barre
for i = 1:2
    text(i, valori_prezzo_B(i), sprintf('%.4f', valori_prezzo_B(i)), 'HorizontalAlignment','center', 'VerticalAlignment','bottom');
end
xticks(1:2);
xticklabels(etichette_metodi);
ylabel('Prezzo');
title('Bond Credit Agricole: confronto metodi (BOOTSTRAP - da CDS spread)');
minY_B = min([valori_prezzo_B; IC95_bootstrap(:)]);
maxY_B = max([valori_prezzo_B; IC95_bootstrap(:)]);
margine_B = 0.08 * (maxY_B - minY_B + eps);
ylim([minY_B - margine_B, maxY_B + 2*margine_B]);
box on; 
hold off;

% Grafico distribuzione PV per traiettoria (pathwise)
figure;
histogram(valore_attuale_traiettoria_file, 60);
grid on;
xlabel('Valore attuale per traiettoria');
ylabel('Frequenza');
title('Distribuzione Monte Carlo del valore attuale (pathwise) - NO BOOTSTRAP');
% Linea verticale + prezzo numerico
hold on;
xline(prezzo_bond_pathwise_file, '--', sprintf(' Prezzo = %.4f', prezzo_bond_pathwise_file), 'LineWidth', 2, 'LabelOrientation','horizontal', 'LabelVerticalAlignment','middle');
hold off;
figure;
histogram(valore_attuale_traiettoria_bootstrap, 60);
grid on;
xlabel('Valore attuale per traiettoria');
ylabel('Frequenza');
title('Distribuzione Monte Carlo del valore attuale (pathwise) - BOOTSTRAP (da CDS spread)');
hold on;
xline(prezzo_bond_pathwise_bootstrap, '--', sprintf(' Prezzo = %.4f', prezzo_bond_pathwise_bootstrap), 'LineWidth', 2, 'LabelOrientation','horizontal', 'LabelVerticalAlignment','middle');
hold off;


%% FUNZIONI INDISPENSABILI
% File: estrai_sigma_da_esercizio_V.m
function sigma_annua_rendimenti_storici_EUROSTOXX50 = estrai_sigma_da_esercizio_V()
    esercizio_V;  
    sigma_annua_rendimenti_storici_EUROSTOXX50 = std(rend_log_eustx, 0) * sqrt(252);
end

% File: estrai_curvaOIS_da_esercizio_VII.m
function [Tabella_Zero_Rate, tasso_riskfree_1M] = estrai_curvaOIS_da_esercizio_VII()
    esercizio_VII;                                                                 % esegue lo script (anche se contiene clear all)
    maturity_anni_OIS = MaturityYR;
    tassi_zero_continui = ZeroRate;
    termine_tenor = TenorValue;
    unita_tenor = TenorUnit;
    Tabella_Zero_Rate = table(maturity_anni_OIS, tassi_zero_continui, 'VariableNames', {'Maturity', 'ZeroRate'});
    indice_1M = (termine_tenor==1) & (unita_tenor=="MO");
    if any(indice_1M)
        tasso_riskfree_1M = tassi_zero_continui(indice_1M);
    else
        error("Nel file curvaEUROIS.xlsx non trovo la riga 1 MO (controlla Term/Unit).");
    end
end

% Bootstrap probabilità di default Credit Agricole (da CDS spread)
function Tabella_Curva_Default_Bootstrappata = bootstrap_probabilita_default_da_CDS(Tabella_CDS_emittente, Tabella_Zero_Rate_OIS, data_valutazione_t0, maturity_massima_anni, recovery_rate)
    if nargin < 5 || isempty(recovery_rate)
        recovery_rate = 0.4;
    end
    if ~all(ismember(["Maturity","Spread"], string(Tabella_CDS_emittente.Properties.VariableNames)))
        error("Tabella_CDS_emittente deve contenere almeno le colonne 'Maturity' e 'Spread'.");
    end
    % Estrazione dati grezzi
    maturity_grezza = Tabella_CDS_emittente.("Maturity");
    spread_grezzo = Tabella_CDS_emittente.("Spread");
    % Conversione maturità in anni (double) rispetto a t0
    % Mantengo anche una versione "originale" per reporting
    if isdatetime(maturity_grezza)
        maturity_anni = days(maturity_grezza - data_valutazione_t0) / 360;
        maturity_originale = maturity_grezza;
    elseif isnumeric(maturity_grezza)
        maturity_anni = maturity_grezza(:);
        maturity_originale = maturity_grezza;
        if any(isfinite(maturity_anni)) && median(maturity_anni(isfinite(maturity_anni))) > 10000
            maturity_datetime = datetime(maturity_anni, "ConvertFrom", "excel");
            maturity_originale = maturity_datetime;
            maturity_anni = days(maturity_datetime - data_valutazione_t0) / 360;
        end
    elseif isstring(maturity_grezza) || iscell(maturity_grezza)
        try
            maturity_datetime = datetime(maturity_grezza);
            maturity_originale = maturity_datetime;
            maturity_anni = days(maturity_datetime - data_valutazione_t0) / 360;
        catch
            error("Formato 'Maturity' nella tabella CDS non convertibile in datetime. Controlla Excel.");
        end
    else
        error("Formato 'Maturity' non gestito nella tabella CDS.");
    end
    spread = spread_grezzo(:);
    % Pulizia dati e filtro orizzonte
    indici_validi = isfinite(maturity_anni) & maturity_anni > 0 & isfinite(spread);
    maturity_anni = maturity_anni(indici_validi);
    spread = spread(indici_validi);
    % Tengo tutte le maturità <= maturity_massima_anni
    indici_entro_orizzonte = maturity_anni <= maturity_massima_anni;
    maturity_anni_entro = maturity_anni(indici_entro_orizzonte);
    spread_entro = spread(indici_entro_orizzonte);
    % Se non ho nodi entro orizzonte, non posso bootstrappare
    if isempty(maturity_anni_entro)
        error("Dati CDS insufficienti: nessuna maturità <= maturity_massima_anni.");
    end
    % Se manca un nodo esattamente a maturity_massima_anni, lo creo interpolando lo spread
    ho_nodo_esatto = any(abs(maturity_anni_entro - maturity_massima_anni) < 1e-6);   
    if ~ho_nodo_esatto
        % Per interpolare lo spread al tempo target servono dati anche oltre (oppure uso l'ultimo valore disponibile)
        maturity_anni_tutti = maturity_anni;
        spread_tutti = spread;   
        % Ordino per sicurezza (interp1 richiede ascendente per comportamento stabile)
        [maturity_anni_tutti, indici_ordinati] = sort(maturity_anni_tutti);
        spread_tutti = spread_tutti(indici_ordinati);
        % Se esistono scadenze sia sotto che sopra, interpolo linearmente; altrimenti uso flat sull'ultimo disponibile
        if any(maturity_anni_tutti < maturity_massima_anni) && any(maturity_anni_tutti > maturity_massima_anni)
            spread_a_maturity = interp1(maturity_anni_tutti, spread_tutti, maturity_massima_anni, 'linear');
        else
            spread_a_maturity = spread_entro(end);                          % flat sull'ultimo nodo disponibile entro orizzonte
        end    
        maturity_anni_entro = [maturity_anni_entro; maturity_massima_anni];
        spread_entro = [spread_entro; spread_a_maturity];
    end    
    % Da qui in poi uso questi vettori (entro orizzonte + eventuale nodo 4Y sintetico)
    maturity_anni = maturity_anni_entro;
    spread = spread_entro;
    if median(spread) > 1
        spread_annuo = spread / 10000;                                      % basis points -> decimale
    else
        spread_annuo = spread;                                              % già in decimale
    end
    [maturity_anni_ordinate, indice_sort] = sort(maturity_anni);
    spread_annuo_ordinato = spread_annuo(indice_sort);
    [maturity_anni_uniche, ~, gruppi] = unique(maturity_anni_ordinate);
    spread_annuo_unico = accumarray(gruppi, spread_annuo_ordinato, [], @mean);
    % Discount factors OIS ai nodi CDS (interp log-Discount_Factor)
    discount_factor_nodi_OIS = exp(-Tabella_Zero_Rate_OIS.ZeroRate .* Tabella_Zero_Rate_OIS.Maturity);
    discount_factor_nodi_CDS = exp(interp1(Tabella_Zero_Rate_OIS.Maturity, log(discount_factor_nodi_OIS), maturity_anni_uniche, "linear", "extrap"));
    % Hazard rate piecewise-flat + mid-point approximation (senza funzioni annidate)
    Loss_Given_Default = (1 - recovery_rate);
    frequenza_pagamenti_CDS = 4;                 
    passo_pagamenti_CDS = 1 / frequenza_pagamenti_CDS;
    numero_nodi = numel(maturity_anni_uniche);
    hazard_rate_piecewise = zeros(numero_nodi, 1);
    probabilita_survival = zeros(numero_nodi, 1);
    probabilita_default = zeros(numero_nodi, 1);    
    % Funzione Discount_Factor coerente con il tuo interp su log-Discount_Factor (riuso discount_factor_nodi_OIS già calcolati sopra)
    Discount_Factor_OIS = @(t) exp(interp1(Tabella_Zero_Rate_OIS.Maturity, log(discount_factor_nodi_OIS), t, "linear", "extrap"));
    for k = 1:numero_nodi
        spread_k = spread_annuo_unico(k);
        T_k = maturity_anni_uniche(k);   
        % Griglia pagamenti premium fino a T_k (quarterly) + includo T_k se non coincide esattamente
        tempi_pagamento = (passo_pagamenti_CDS:passo_pagamenti_CDS:T_k)';
        if isempty(tempi_pagamento) || abs(tempi_pagamento(end) - T_k) > 1e-12
            tempi_pagamento = [tempi_pagamento; T_k];
        end
        tempi_precedenti = [0; tempi_pagamento(1:end-1)];
        year_fraction_premium = tempi_pagamento - tempi_precedenti;
        tempi_mezzo = (tempi_precedenti + tempi_pagamento) / 2; 
        % Equazione nodale bootstrap CDS: risolvo hazard_k imponendo Net_Present_Value_premium(hazard_k) - Net_Present_Value_default(hazard_k) = 0 sul CDS a scadenza T_k
        equazione_bootstrap_hazard_CDS = @(hazard_k) calcola_Net_Present_Value_CDS_nodo(hazard_k, k, spread_k, Loss_Given_Default, tempi_pagamento, tempi_precedenti, year_fraction_premium, tempi_mezzo, maturity_anni_uniche, hazard_rate_piecewise, Discount_Factor_OIS); 
        % Bracketing robusto per la radice
        hazard_limite_inferiore = 1e-8;
        hazard_limite_superiore = 5.0;
        valore_equazione_al_lower_bound = equazione_bootstrap_hazard_CDS(hazard_limite_inferiore);
        valore_equazione_al_upper_bound = equazione_bootstrap_hazard_CDS(hazard_limite_superiore);
        tentativi = 0;
        while sign(valore_equazione_al_lower_bound) == sign(valore_equazione_al_upper_bound) && tentativi < 10
            hazard_limite_superiore = hazard_limite_superiore * 2;
            valore_equazione_al_upper_bound = equazione_bootstrap_hazard_CDS(hazard_limite_superiore);
            tentativi = tentativi + 1;
        end
        if sign(valore_equazione_al_lower_bound) == sign(valore_equazione_al_upper_bound)
            error("Bootstrap CDS: impossibile individuare un intervallo [h_inf, h_sup] con cambio di segno per k=%d (T=%.6f). Verifica spread CDS e curva di sconto OIS.", k, T_k);
        end  
        hazard_rate_piecewise(k) = fzero(equazione_bootstrap_hazard_CDS, [hazard_limite_inferiore, hazard_limite_superiore]);    
        probabilita_survival(k) = calcola_survival_piecewise(T_k, k, maturity_anni_uniche, hazard_rate_piecewise, hazard_rate_piecewise(k));
        probabilita_default(k) = 1 - probabilita_survival(k);
    end
    % Ricostruisco una maturity "originale" per reporting:
    % - per i nodi che provengono dal file: uso la prima occorrenza disponibile
    % - per il nodo sintetico: imposto NaT (se datetime) o NaN (se numerico)
    if isdatetime(maturity_grezza)
        maturity_originale_uniche = NaT(numel(maturity_anni_uniche), 1);
        maturity_grezza_valida = maturity_grezza(indici_validi);  
        maturity_anni_valida = days(maturity_grezza_valida - data_valutazione_t0) / 360;
        for k = 1:numel(maturity_anni_uniche)
            % Trovo la maturity grezza più vicina al nodo (se esiste)
            [differenza_minima_anni, indice_minimo] = min(abs(maturity_anni_valida - maturity_anni_uniche(k)));
            if isfinite(differenza_minima_anni) && differenza_minima_anni < 1e-4                        % tolleranza = 1e-6 ~0.04 giorni
                maturity_originale_uniche(k) = maturity_grezza_valida(indice_minimo);
            end
        end
        indice_target = find(abs(maturity_anni_uniche - maturity_massima_anni) < 1e-6, 1, 'first');
        if ~isempty(indice_target)
            maturity_originale_uniche(indice_target) = datetime(year(data_valutazione_t0) + round(maturity_massima_anni), 12, 20);
        end
    else
        % Caso non-datetime: metto NaN di default
        maturity_originale_uniche = NaN(numel(maturity_anni_uniche), 1);
    end
    Tabella_Curva_Default_Bootstrappata = table(maturity_originale_uniche, maturity_anni_uniche, spread_annuo_unico, discount_factor_nodi_CDS, probabilita_survival, probabilita_default, hazard_rate_piecewise, 'VariableNames', {'Maturity_Originale', 'Maturity_Anni', 'Spread_Annuale', 'Discount_Factor_OIS', 'Survival_Probability', 'Default_Probability', 'Hazard_Rate'} );
    % Check survival deve essere non crescente
    if any(diff(Tabella_Curva_Default_Bootstrappata.Survival_Probability) > 1e-10)
        warning("Curva survival bootstrappata non monotona decrescente: verifica spread e input.");
    end
end

% Survival probability S(0,t) con hazard rate a tratti costante (piecewise-flat) fino al nodo k (ultimo tratto con hazard candidato)
function probabilita_survival_0_t = calcola_survival_piecewise(t, k, maturity_anni_uniche, hazard_rate_piecewise, hazard_candidato)
% Calcola probabilita_survival_0_t(0,t) con hazard piecewise-flat:
% - intervalli 1...k-1 usano hazard_rate_piecewise(1...k-1)
% - intervallo k usa hazard_candidato
    if t <= 0
        probabilita_survival_0_t = 1.0;
        return;
    end
    probabilita_survival_0_t = 1.0;
    t_inizio = 0.0;
    % Intervalli completi 1...k-1
    for j = 1:(k-1)
        if t <= maturity_anni_uniche(j)
            probabilita_survival_0_t = probabilita_survival_0_t * exp(-hazard_rate_piecewise(j) * (t - t_inizio));
            return;
        else
            probabilita_survival_0_t = probabilita_survival_0_t * exp(-hazard_rate_piecewise(j) * (maturity_anni_uniche(j) - t_inizio));
            t_inizio = maturity_anni_uniche(j);
        end
    end
    % Intervallo k (o oltre) con hazard_candidato fino a t
    probabilita_survival_0_t = probabilita_survival_0_t * exp(-hazard_candidato * (t - t_inizio));
end

% Equazione di parità (NPV=0) del CDS al nodo k: premium leg e default leg con accrual stimato al midpoint
function Net_Present_Value = calcola_Net_Present_Value_CDS_nodo(hazard_k, k, spread_k, Loss_Given_Default, tempi_pagamento, tempi_precedenti, year_fraction_premium, tempi_mezzo, maturity_anni_uniche, hazard_rate_piecewise, Discount_Factor_OIS)
    Survival_ti = zeros(numel(tempi_pagamento),1);
    Survival_tim1 = zeros(numel(tempi_pagamento),1);
    for i = 1:numel(tempi_pagamento)
        Survival_ti(i) = calcola_survival_piecewise(tempi_pagamento(i), k, maturity_anni_uniche, hazard_rate_piecewise, hazard_k);
        Survival_tim1(i) = calcola_survival_piecewise(tempi_precedenti(i), k, maturity_anni_uniche, hazard_rate_piecewise, hazard_k);
    end
    % Probabilità di default per intervallo: P(ti-1,ti) = probabilita_survival_0_t(ti-1) - probabilita_survival_0_t(ti)
    probabilita_default_intervallo = Survival_tim1 - Survival_ti;
    Discount_Factor_ti = Discount_Factor_OIS(tempi_pagamento);
    Discount_Factor_mezzo = Discount_Factor_OIS(tempi_mezzo);
    % Mid-point approximation: A, B, C
    A_premium_leg = sum(Survival_ti .* Discount_Factor_ti .* year_fraction_premium);
    B_accrual_premium_in_default = sum(probabilita_default_intervallo .* Discount_Factor_mezzo .* (year_fraction_premium/2));
    C_default_leg = sum(probabilita_default_intervallo .* Discount_Factor_mezzo);
    Net_Present_Value = spread_k * (A_premium_leg + B_accrual_premium_in_default) - Loss_Given_Default * C_default_leg;
end