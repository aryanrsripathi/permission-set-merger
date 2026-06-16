import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPermissionSets   from '@salesforce/apex/PermissionSetMergerController.getPermissionSets';
import mergePermissionSets from '@salesforce/apex/PermissionSetMergerController.mergePermissionSets';

export default class PermissionSetMerger extends LightningElement {

    @track currentStep       = 1;
    @track allPermSets       = [];
    @track availablePermSets = [];
    @track selectedPermSets  = [];
    @track filterText        = '';
    @track newLabel          = '';
    @track newApiName        = '';
    @track newDescription    = '';
    @track isMerging         = false;
    @track mergeComplete     = false;
    @track mergeResult       = null;
    @track errorMessage      = '';

    _apiNameManuallyEdited = false;
    _highlightedAvailable  = new Set();
    _highlightedSelected   = new Set();
    isLoading              = false;

    @wire(getPermissionSets)
    wiredPermSets({ error, data }) {
        if (data) {
            this.allPermSets       = data.map(ps => ({ ...ps, highlighted: false }));
            this.availablePermSets = [...this.allPermSets];
            this.selectedPermSets  = [];
            this.isLoading = false;
        } else if (error) {
            this.isLoading = false;
            this._showToast('Error', this._errorMsg(error), 'error');
        }
    }

    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get step1Class() { return this._stepClass(1); }
    get step2Class() { return this._stepClass(2); }
    get step3Class() { return this._stepClass(3); }
    _stepClass(n) {
        const base = 'slds-col step-pill';
        if (this.currentStep === n) return base + ' step-active';
        if (this.currentStep > n)  return base + ' step-done';
        return base + ' step-pending';
    }

    get filteredAvailable() {
        const q = this.filterText.toLowerCase();
        return this.availablePermSets
            .filter(ps => !q || ps.label.toLowerCase().includes(q) || ps.name.toLowerCase().includes(q))
            .map(ps => ({ ...ps, cssClass: 'ps-item' + (ps.highlighted ? ' ps-item-highlighted' : '') }));
    }
    get selectedPermSetsDisplay() {
        return this.selectedPermSets.map(ps => ({
            ...ps,
            selectedCssClass: 'ps-item' + (this._highlightedSelected.has(ps.id) ? ' ps-item-highlighted' : '')
        }));
    }
    get availableCount()         { return this.filteredAvailable.length; }
    get selectedCount()          { return this.selectedPermSets.length; }
    get noAvailable()            { return this.filteredAvailable.length === 0; }
    get noSelected()             { return this.selectedPermSets.length === 0; }
    get noAvailableHighlighted() { return this._highlightedAvailable.size === 0; }
    get noSelectedHighlighted()  { return this._highlightedSelected.size === 0; }
    get selectedBadgeClass() {
        return 'slds-badge' + (this.selectedPermSets.length >= 2 ? ' badge-ready' : ' badge-warning');
    }
    get cannotProceedStep1() { return this.selectedPermSets.length < 2; }
    get cannotProceedStep2() { return !this.newLabel.trim() || !this.newApiName.trim(); }
    get hasSuccesses()       { return this.mergeResult?.successes?.length  > 0; }
    get hasWarnings()        { return this.mergeResult?.warnings?.length   > 0; }
    get hasManualItems()     { return this.mergeResult?.manualItems?.length > 0; }
    get newPSSetupUrl()      { return '/lightning/setup/PermSets/home'; }

    handleFilter(e) { this.filterText = e.target.value; }

    handleAvailableClick(e) {
        const id = e.target.closest('[data-id]')?.dataset?.id;
        if (!id) return;
        this._highlightedAvailable.has(id) ? this._highlightedAvailable.delete(id) : this._highlightedAvailable.add(id);
        this._refreshAvailableHighlights();
    }
    handleSelectedClick(e) {
        const id = e.target.closest('[data-id]')?.dataset?.id;
        if (!id) return;
        this._highlightedSelected.has(id) ? this._highlightedSelected.delete(id) : this._highlightedSelected.add(id);
        this._refreshSelectedHighlights();
    }
    handleAddSelected() {
        const toMove = this.availablePermSets.filter(ps => this._highlightedAvailable.has(ps.id));
        toMove.forEach(ps => { ps.highlighted = false; this.selectedPermSets.push(ps); });
        this.availablePermSets = this.availablePermSets.filter(ps => !this._highlightedAvailable.has(ps.id));
        this._highlightedAvailable.clear();
        this._refreshLists();
    }
    handleAddAll() {
        const visible = new Set(this.filteredAvailable.map(ps => ps.id));
        const toMove  = this.availablePermSets.filter(ps => visible.has(ps.id));
        toMove.forEach(ps => { ps.highlighted = false; this.selectedPermSets.push(ps); });
        this.availablePermSets = this.availablePermSets.filter(ps => !visible.has(ps.id));
        this._highlightedAvailable.clear();
        this._refreshLists();
    }
    handleRemoveSelected() {
        const toMove = this.selectedPermSets.filter(ps => this._highlightedSelected.has(ps.id));
        toMove.forEach(ps => { ps.highlighted = false; this.availablePermSets.push(ps); });
        this.selectedPermSets = this.selectedPermSets.filter(ps => !this._highlightedSelected.has(ps.id));
        this._highlightedSelected.clear();
        this._refreshLists();
    }
    handleRemoveAll() {
        this.selectedPermSets.forEach(ps => { ps.highlighted = false; this.availablePermSets.push(ps); });
        this.selectedPermSets = [];
        this._highlightedSelected.clear();
        this._refreshLists();
    }

    handleLabelChange(e) {
        this.newLabel = e.target.value;
        if (!this._apiNameManuallyEdited) {
            this.newApiName = e.target.value.trim()
                .replace(/\s+/g, '_').replace(/[^a-zA-Z0-9_]/g, '').replace(/^[^a-zA-Z]+/, '');
        }
    }
    handleApiNameChange(e)    { this._apiNameManuallyEdited = true; this.newApiName = e.target.value; }
    handleDescriptionChange(e){ this.newDescription = e.target.value; }

    goToStep1() { this.currentStep = 1; this.errorMessage = ''; }
    goToStep2() { if (this.selectedPermSets.length < 2) return; this.currentStep = 2; this.errorMessage = ''; }
    goToStep3() { if (!this.newLabel.trim() || !this.newApiName.trim()) return; this.currentStep = 3; this.mergeComplete = false; this.errorMessage = ''; }

    handleMerge() {
        this.isMerging    = true;
        this.errorMessage = '';
        mergePermissionSets({
            permissionSetIds : this.selectedPermSets.map(ps => ps.id),
            newLabel         : this.newLabel,
            newApiName       : this.newApiName,
            newDescription   : this.newDescription
        })
        .then(result => {
            this.isMerging     = false;
            this.mergeComplete = true;
            this.mergeResult   = result;
            this._showToast('Success', 'Permission set "' + this.newLabel + '" created!', 'success');
        })
        .catch(error => {
            this.isMerging    = false;
            this.errorMessage = this._errorMsg(error);
            this._showToast('Merge Failed', this.errorMessage, 'error');
        });
    }

    handleReset() {
        this.currentStep            = 1;
        this.selectedPermSets       = [];
        this.availablePermSets      = [...this.allPermSets];
        this.filterText             = '';
        this.newLabel               = '';
        this.newApiName             = '';
        this.newDescription         = '';
        this._apiNameManuallyEdited = false;
        this.isMerging              = false;
        this.mergeComplete          = false;
        this.mergeResult            = null;
        this.errorMessage           = '';
        this._highlightedAvailable  = new Set();
        this._highlightedSelected   = new Set();
        this._refreshLists();
    }

    _refreshAvailableHighlights() {
        this.availablePermSets = this.availablePermSets.map(ps => ({
            ...ps, highlighted: this._highlightedAvailable.has(ps.id)
        }));
    }
    _refreshSelectedHighlights() {
        this.selectedPermSets = this.selectedPermSets.map(ps => ({
            ...ps, selectedHighlighted: this._highlightedSelected.has(ps.id)
        }));
    }
    _refreshLists() {
        this.availablePermSets = [...this.availablePermSets];
        this.selectedPermSets  = [...this.selectedPermSets];
    }
    _errorMsg(e) { return e?.body?.message || e?.message || JSON.stringify(e); }
    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant,
            mode: variant === 'error' ? 'sticky' : 'dismissable' }));
    }
}